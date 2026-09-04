// lib/presentation/features/head_manager/dashboard/providers/hm_ai_provider.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/ai_remote_datasource.dart';
import '../../../../../data/models/ai_insights_model.dart';

/// Parsed chat message for the Ask AI panel.
class AiChatMessage {
  final String role; // 'user' | 'ai'
  final String text;
  final DateTime timestamp;
  const AiChatMessage({
    required this.role,
    required this.text,
    required this.timestamp,
  });
}

// ── Insights state ─────────────────────────────────────────────────────────
class HmAiInsightsState {
  final AiInsightsModel? insights;
  final bool isLoading;

  /// Loader label phase: 'analyzing' → 'generating' (client-side only; the
  /// actual work happens in the edge function).
  final String phase;
  final String? error;

  const HmAiInsightsState({
    this.insights,
    this.isLoading = false,
    this.phase = '',
    this.error,
  });

  bool get hasInsights => insights != null;

  HmAiInsightsState copyWith({
    AiInsightsModel? insights,
    bool? isLoading,
    String? phase,
    String? error,
  }) =>
      HmAiInsightsState(
        insights: insights ?? this.insights,
        isLoading: isLoading ?? this.isLoading,
        phase: phase ?? '',
        error: error,
      );
}

class HmAiInsightsNotifier extends StateNotifier<HmAiInsightsState> {
  final AiRemoteDataSource _ds;
  Timer? _phaseTimer;
  int _generationSeq = 0;

  HmAiInsightsNotifier(this._ds) : super(const HmAiInsightsState());

  @override
  void dispose() {
    _phaseTimer?.cancel();
    super.dispose();
  }

  /// Generates (or regenerates) insights for the given month. The backend
  /// re-reads the verified stats from PostgreSQL on every call, so a new
  /// payment/loan is always reflected in the next generation.
  Future<void> generate({String? month}) async {
    final seq = ++_generationSeq;
    _phaseTimer?.cancel();
    state = state.copyWith(isLoading: true, phase: 'analyzing', error: null);

    // After ~2.5s still running, flip the loader label to "generating".
    _phaseTimer = Timer(const Duration(milliseconds: 2500), () {
      if (seq == _generationSeq && state.isLoading) {
        state = state.copyWith(phase: 'generating');
      }
    });

    try {
      final insights = await _ds.generateInsights(month: month);
      if (seq != _generationSeq) return;
      _phaseTimer?.cancel();
      state = state.copyWith(
        insights: insights,
        isLoading: false,
        phase: '',
        error: null,
      );
    } catch (e) {
      if (seq != _generationSeq) return;
      _phaseTimer?.cancel();
      state = state.copyWith(
        isLoading: false,
        phase: '',
        error: ErrorHandler.handle(e).message,
      );
    }
  }

  /// Keeps the previously generated result but marks it stale/removed so the
  /// panel can reset to the idle state (used when the month changes).
  void reset() {
    _generationSeq++;
    _phaseTimer?.cancel();
    state = const HmAiInsightsState();
  }
}

final hmAiInsightsProvider =
    StateNotifierProvider<HmAiInsightsNotifier, HmAiInsightsState>((ref) {
  return HmAiInsightsNotifier(sl<AiRemoteDataSource>());
});

// ── Ask AI chat state ──────────────────────────────────────────────────────
class HmAiChatState {
  final List<AiChatMessage> messages;
  final bool isBusy;
  final String? error;

  const HmAiChatState({
    this.messages = const [],
    this.isBusy = false,
    this.error,
  });

  HmAiChatState copyWith({
    List<AiChatMessage>? messages,
    bool? isBusy,
    String? error,
  }) =>
      HmAiChatState(
        messages: messages ?? this.messages,
        isBusy: isBusy ?? this.isBusy,
        error: error,
      );
}

class HmAiChatNotifier extends StateNotifier<HmAiChatState> {
  final AiRemoteDataSource _ds;
  HmAiChatNotifier(this._ds) : super(const HmAiChatState());

  Future<void> ask({
    required String question,
    String? month,
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || state.isBusy) return;

    final userMsg =
        AiChatMessage(role: 'user', text: trimmed, timestamp: DateTime.now());
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isBusy: true,
      error: null,
    );

    try {
      final answer = await _ds.ask(question: trimmed, month: month);
      state = state.copyWith(
        messages: [
          ...state.messages,
          AiChatMessage(
            role: 'ai',
            text: answer.answer,
            timestamp: answer.generatedAt,
          ),
        ],
        isBusy: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        messages: [
          ...state.messages,
          AiChatMessage(
            role: 'ai',
            text: ErrorHandler.handle(e).message,
            timestamp: DateTime.now(),
          ),
        ],
        isBusy: false,
        error: null,
      );
    }
  }
}

final hmAiChatProvider =
    StateNotifierProvider<HmAiChatNotifier, HmAiChatState>((ref) {
  return HmAiChatNotifier(sl<AiRemoteDataSource>());
});