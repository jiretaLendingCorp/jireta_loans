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

  /// Manila-day date range (ISO, UTC instant) na ipinapasa sa backend bilang
  /// `date_from` / `date_to` — naka-apply sa `created_at` ng application.
  final String? dateFrom;
  final String? dateTo;

  const HmInOfficeState({
    this.applications = const [],
    this.isLoading = false,
    this.error,
    this.dateFrom,
    this.dateTo,
  });

  /// Sentinel para sa `dateFrom` / `dateTo` sa [copyWith]: iba ang "hindi
  /// ipinasa" (panatilihin ang datos) sa "ipinasang null" (i-clear ang
  /// filter). Kung `??` lang ang gamit, hindi maibabalik sa walang filter
  /// dahil `null ?? oldValue` = oldValue.
  static const _unset = Object();

  HmInOfficeState copyWith({
    List<Map<String, dynamic>>? applications,
    bool? isLoading,
    String? error,
    Object? dateFrom = _unset,
    Object? dateTo = _unset,
  }) =>
      HmInOfficeState(
        applications: applications ?? this.applications,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        dateFrom: dateFrom == _unset ? this.dateFrom : dateFrom as String?,
        dateTo: dateTo == _unset ? this.dateTo : dateTo as String?,
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
        // Isinasama ang nakatagong date range — kung wala, hindi na ito
        // kailangan pang salain sa app.
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      state = state.copyWith(applications: data, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  /// Date-range filter ng In-Office tab (`created_at` ng aplikasyon, Manila
  /// day). `(null, null)` = i-clear ang filter.
  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
    load();
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
      // Itago ang DAHILAN sa state.error — ipinapakita ito ng wizard sa
      // snackbar kapag bigong mag-save (dating generic na mensahe lang, kaya
      // mahirap i-debug ang 400/500 mula sa backend).
      state = state.copyWith(error: ErrorHandler.handle(e).message);
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
      // Silent refresh: ina-update ang listahan nang WALANG isLoading spinner
      // (dating nag-fla-flash ang buong table pagkatapos ng Submit).
      await load(silent: true);
      return res;
    } catch (e) {
      // ignore: avoid_print
      print('[HmInOffice] submit failed for $applicationId: ${ErrorHandler.handle(e).message}');
      return null;
    }
  }

  /// Step-3 account submit: creates + auto-verifies the lender account
  /// (no loan). Returns backend payload (lender_id, login_phone, ...).
  Future<Map<String, dynamic>?> submitAccount(String applicationId) async {
    try {
      final res = await _ds.submitAccount(applicationId: applicationId);
      // Silent refresh (tingnan ang submitApplication): hindi na nag-re-reload
      // nang buo ang In-Office table pagkatapos ng step-3 Submit.
      await load(silent: true);
      return res;
    } catch (e) {
      // Itago ang DAHILAN (hal. "Step 3 is incomplete: missing selfie") sa
      // state.error para hindi na generic na "Account submit failed" lang ang
      // nakikita ng staff.
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      // ignore: avoid_print
      print('[HmInOffice] submitAccount failed for $applicationId: ${ErrorHandler.handle(e).message}');
      return null;
    }
  }

  /// Legacy bool wrapper for callers that only care about success/failure
  Future<bool> submitApplicationBool(String applicationId) async {
    final r = await submitApplication(applicationId);
    return r != null;
  }

  /// Full wizard detail (steps 1-5 + linked loan + co-makers + account
  /// upgrade status) used by View mode / continue editing.
  Future<Map<String, dynamic>?> getDetails(String applicationId) async {
    try {
      return await _ds.getDetails(applicationId: applicationId);
    } catch (e) {
      // ignore: avoid_print
      print('[HmInOffice] getDetails failed for $applicationId: ${ErrorHandler.handle(e).message}');
      return null;
    }
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
