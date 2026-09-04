// lib/presentation/features/head_manager/dashboard/providers/hm_ai_provider.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'ts': timestamp.toIso8601String(),
      };

  static AiChatMessage fromJson(Map<String, dynamic> json) => AiChatMessage(
        role: json['role']?.toString() ?? 'ai',
        text: json['text']?.toString() ?? '',
        timestamp:
            DateTime.tryParse(json['ts']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// A conversation archived to the "Recent" list so the user can reopen it.
class SavedAiChat {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<AiChatMessage> messages;
  const SavedAiChat({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  static SavedAiChat fromJson(Map<String, dynamic> json) => SavedAiChat(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Chat',
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
        messages: ((json['messages'] as List?) ?? [])
            .whereType<Map>()
            .map((m) => AiChatMessage.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

// ── Local persistence (recent chats stay on the device — never sent to the
//    backend; the AI conversation contains no PII by design) ──────────────
class _AiChatStore {
  static const _key = 'ai_chat_recent_v1';
  static const _max = 10;

  static Future<List<SavedAiChat>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List? ?? [];
      return list
          .whereType<Map>()
          .map((m) => SavedAiChat.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<SavedAiChat> chats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(chats.take(_max).map((c) => c.toJson()).toList()),
      );
    } catch (_) {
      // Best-effort persistence — never break the chat over storage errors.
    }
  }
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

  /// Archived conversations the user can reopen (persisted locally).
  final List<SavedAiChat> recentChats;

  const HmAiChatState({
    this.messages = const [],
    this.isBusy = false,
    this.error,
    this.recentChats = const [],
  });

  HmAiChatState copyWith({
    List<AiChatMessage>? messages,
    bool? isBusy,
    String? error,
    List<SavedAiChat>? recentChats,
  }) =>
      HmAiChatState(
        messages: messages ?? this.messages,
        isBusy: isBusy ?? this.isBusy,
        error: error,
        recentChats: recentChats ?? this.recentChats,
      );
}

class HmAiChatNotifier extends StateNotifier<HmAiChatState> {
  final AiRemoteDataSource _ds;

  /// Identifies the conversation currently open (for update-on-New-Chat).
  String? _sessionId;
  bool _loaded = false;
  Future<void>? _loading;
  int _idSeq = 0;

  HmAiChatNotifier(this._ds) : super(const HmAiChatState());

  @override
  void dispose() {
    _loading = null;
    super.dispose();
  }

  String _newId() =>
      'chat_${DateTime.now().millisecondsSinceEpoch}_${_idSeq++}';

  /// Loads the locally-persisted recent chats (once).
  Future<void> _ensureLoaded() async {
    if (_loaded || _loading != null) return;
    final loading = _AiChatStore.load().then((chats) {
      if (mounted) state = state.copyWith(recentChats: chats);
    });
    _loading = loading;
    await loading;
    _loaded = true;
    _loading = null;
  }

  /// Public entry to make sure recent chats are loaded (called when the Ask
  /// AI modal opens).
  Future<void> refreshRecent() => _ensureLoaded();

  static String _titleOf(List<AiChatMessage> messages) {
    String first = '';
    for (final m in messages) {
      if (m.role == 'user') {
        first = m.text.trim();
        break;
      }
    }
    final raw = first.isEmpty ? 'Chat' : first;
    return raw.length > 42 ? '${raw.substring(0, 42)}…' : raw;
  }

  /// New Chat — archives the current conversation into Recent (so the user
  /// can come back to it), then clears the screen.
  Future<void> clear() async {
    await _ensureLoaded();
    final hasContent =
        state.messages.isNotEmpty && state.messages.any((m) => m.role == 'user');
    if (hasContent) {
      final saved = SavedAiChat(
        id: _sessionId ?? _newId(),
        title: _titleOf(state.messages),
        updatedAt: DateTime.now(),
        messages: List<AiChatMessage>.from(state.messages),
      );
      final others =
          state.recentChats.where((c) => c.id != saved.id).toList();
      final recent = [saved, ...others];
      await _AiChatStore.save(recent);
      if (mounted) {
        state = state.copyWith(
          messages: const [],
          recentChats: recent,
          error: null,
        );
      }
    } else if (mounted) {
      state = state.copyWith(messages: const [], error: null);
    }
    _sessionId = null;
  }

  /// Reopens a saved conversation from the Recent list.
  Future<void> openSaved(SavedAiChat chat) async {
    await _ensureLoaded();
    _sessionId = chat.id;
    if (mounted) {
      state = state.copyWith(
        messages: List<AiChatMessage>.from(chat.messages),
        error: null,
      );
    }
  }

  /// Removes a single conversation from Recent.
  Future<void> removeSaved(String id) async {
    await _ensureLoaded();
    final recent =
        state.recentChats.where((c) => c.id != id).toList();
    await _AiChatStore.save(recent);
    if (mounted) state = state.copyWith(recentChats: recent);
    if (_sessionId == id) _sessionId = null;
  }

  Future<void> ask({
    required String question,
    String? month,
  }) async {
    await _ensureLoaded();
    final trimmed = question.trim();
    if (trimmed.isEmpty || state.isBusy) return;

    // Fresh session when starting from an empty conversation.
    if (state.messages.isEmpty) _sessionId = _newId();

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