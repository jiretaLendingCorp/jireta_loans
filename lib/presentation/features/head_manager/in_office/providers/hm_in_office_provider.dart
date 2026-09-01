// lib/presentation/features/head_manager/in_office/providers/hm_in_office_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/in_office_remote_datasource.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmInOfficeState {
  final List<Map<String, dynamic>> applications;
  final bool isLoading;
  final String? error;

  const HmInOfficeState({
    this.applications = const [],
    this.isLoading = false,
    this.error,
  });

  HmInOfficeState copyWith({
    List<Map<String, dynamic>>? applications,
    bool? isLoading,
    String? error,
  }) =>
      HmInOfficeState(
        applications: applications ?? this.applications,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

final hmInOfficeProvider =
    AutoDisposeStateNotifierProvider<HmInOfficeNotifier, HmInOfficeState>(
        (ref) {
  return HmInOfficeNotifier(
      sl<InOfficeRemoteDataSource>(), sl<LoanRemoteDataSource>());
});

class HmInOfficeNotifier extends StateNotifier<HmInOfficeState>
    with RealtimeRefreshMixin {
  final InOfficeRemoteDataSource _ds;
  final LoanRemoteDataSource _loanDs;
  HmInOfficeNotifier(this._ds, this._loanDs) : super(const HmInOfficeState()) {
    bindRealtimeRefresh(['in_office_applications'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({String? status, int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _ds.getList(
        status: status == 'all' ? null : status,
        page: page,
      );
      state = state.copyWith(applications: data, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setStatus(String status) => load(status: status);

  Future<String?> createDraft() async {
    try {
      final data = await _ds.createDraft();
      return data['application_id'] as String?;
    } catch (e) {
      // Surface error via log so 400/500 reason is not silently lost.
      // ignore: avoid_print
      print('[HmInOffice] createDraft failed: ${ErrorHandler.handle(e).message}');
      return null;
    }
  }

  Future<bool> saveStep(
      String applicationId, int step, Map<String, dynamic> data) async {
    try {
      await _ds.saveStep(applicationId: applicationId, step: step, data: data);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[HmInOffice] saveStep $step failed for $applicationId: ${ErrorHandler.handle(e).message}');
      return false;
    }
  }

  /// Returns the raw backend response (may contain pending_upgrade flag).
  /// Caller should inspect `pending_upgrade` == true to show "account created, awaiting KYC" vs loan converted.
  Future<Map<String, dynamic>?> submitApplication(String applicationId) async {
    try {
      final res = await _ds.submit(applicationId: applicationId);
      await load();
      return res;
    } catch (e) {
      // ignore: avoid_print
      print('[HmInOffice] submit failed for $applicationId: ${ErrorHandler.handle(e).message}');
      return null;
    }
  }

  /// Legacy bool wrapper for callers that only care about success/failure
  Future<bool> submitApplicationBool(String applicationId) async {
    final r = await submitApplication(applicationId);
    return r != null;
  }

  Future<Map<String, dynamic>?> getSchedulePreview(
      double principal, String frequency,
      {int? termPeriods}) async {
    try {
      return await _loanDs.getSchedulePreview(principal, frequency,
          termPeriods: termPeriods);
    } catch (e) {
      return null;
    }
  }
}
