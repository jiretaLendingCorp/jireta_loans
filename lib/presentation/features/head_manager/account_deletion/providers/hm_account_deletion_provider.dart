// lib/presentation/features/head_manager/account_deletion/providers/hm_account_deletion_provider.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/account_deletion_remote_datasource.dart';
import '../../../../../data/models/account_deletion_request_model.dart';

class HmAccountDeletionState {
  final List<AccountDeletionRequestModel> requests;
  final bool isLoading;
  final bool isProcessing;
  final String filter;
  final String? error;

  const HmAccountDeletionState({
    this.requests = const [],
    this.isLoading = false,
    this.isProcessing = false,
    this.filter = 'pending',
    this.error,
  });
}

class HmAccountDeletionNotifier extends StateNotifier<HmAccountDeletionState> {
  final AccountDeletionRemoteDataSource _ds;
  int _requestSeq = 0;

  HmAccountDeletionNotifier(this._ds) : super(const HmAccountDeletionState());

  Future<void> load({bool silent = false}) async {
    final seq = ++_requestSeq;
    if (!silent) {
      state = HmAccountDeletionState(
        requests: state.requests,
        isLoading: true,
        filter: state.filter,
        isProcessing: state.isProcessing,
      );
    }

    try {
      final rows = await _ds.listRequests(status: state.filter);
      if (seq != _requestSeq) return;
      state = HmAccountDeletionState(
        requests: rows,
        filter: state.filter,
      );
    } catch (error) {
      if (seq != _requestSeq) return;
      state = HmAccountDeletionState(
        requests: state.requests,
        filter: state.filter,
        error: _messageFor(error),
      );
    }
  }

  void setFilter(String filter) {
    if (filter == state.filter) return;
    state = HmAccountDeletionState(
      requests: state.requests,
      filter: filter,
      isProcessing: state.isProcessing,
    );
    load();
  }

  Future<String?> approve({
    required String requestId,
    String? notes,
  }) =>
      _process(requestId: requestId, action: 'approve', notes: notes);

  Future<String?> reject({
    required String requestId,
    required String notes,
  }) =>
      _process(requestId: requestId, action: 'reject', notes: notes);

  Future<String?> _process({
    required String requestId,
    required String action,
    String? notes,
  }) async {
    if (state.isProcessing) return 'Another request is still being processed.';

    state = HmAccountDeletionState(
      requests: state.requests,
      filter: state.filter,
      isProcessing: true,
    );

    try {
      await _ds.processRequest(
        requestId: requestId,
        action: action,
        notes: notes,
      );
      await load(silent: true);
      return null;
    } catch (error) {
      return _messageFor(error);
    } finally {
      if (mounted) {
        state = HmAccountDeletionState(
          requests: state.requests,
          filter: state.filter,
        );
      }
    }
  }

  String _messageFor(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final serverError = data['error'];
        if (serverError is Map && serverError['message'] is String) {
          final message = (serverError['message'] as String).trim();
          if (message.isNotEmpty) return message;
        }
      }
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
    }
    return 'Something went wrong. Please check your connection and try again.';
  }
}

final hmAccountDeletionProvider = AutoDisposeStateNotifierProvider<
    HmAccountDeletionNotifier, HmAccountDeletionState>(
  (ref) => HmAccountDeletionNotifier(sl<AccountDeletionRemoteDataSource>()),
);
