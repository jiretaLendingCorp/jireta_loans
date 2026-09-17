// lib/presentation/features/employee/in_office/providers/emp_in_office_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/in_office_remote_datasource.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

final empInOfficeProvider = AutoDisposeStateNotifierProvider<
    EmpInOfficeNotifier, AsyncValue<Map<String, dynamic>>>((ref) {
  return EmpInOfficeNotifier(
      sl<InOfficeRemoteDataSource>(), sl<LoanRemoteDataSource>());
});

class EmpInOfficeNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>>
    with RealtimeRefreshMixin {
  final InOfficeRemoteDataSource _ds;
  final LoanRemoteDataSource _loanDs;

  /// Manila-day date range (`SearchDateFilter.fromParam/toParam`) na ipinapasa
  /// sa backend bilang `date_from` / `date_to` — naka-apply sa `created_at` ng
  /// application. Nasa notifier ito (hindi sa state) dahil
  /// `AsyncValue<Map<String, dynamic>>` ang state ng provider na ito.
  String? _dateFrom;
  String? _dateTo;

  EmpInOfficeNotifier(this._ds, this._loanDs)
      : super(const AsyncData({'items': [], 'total': 0})) {
    bindRealtimeRefresh(['in_office_applications'],
        refresh: () => loadList(silent: true));
    loadList();
  }

  Future<void> loadList(
      {String? status, int page = 1, bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    try {
      final data = await _ds.getList(
        status: status == 'all' ? null : status,
        page: page,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      state = AsyncData({'items': data, 'total': data.length});
    } catch (e, s) {
      if (silent && state is AsyncData) return;
      state = AsyncError(e, s);
    }
  }

  /// Date-range filter ng In-Office tab. `(null, null)` = i-clear ang filter.
  void setDateRange(String? from, String? to) {
    _dateFrom = from;
    _dateTo = to;
    loadList();
  }

  void setStatus(String status) => loadList(status: status);

  Future<String?> createDraft() async {
    try {
      final data = await _ds.createDraft();
      return data['application_id'] as String?;
    } catch (e) {
      // ignore: avoid_print
      print('[EmpInOffice] createDraft failed: ${ErrorHandler.handle(e).message}');
      return null;
    }
  }

  Future<bool> saveStep({
    required String applicationId,
    required int step,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _ds.saveStep(applicationId: applicationId, step: step, data: data);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[EmpInOffice] saveStep $step failed: ${ErrorHandler.handle(e).message}');
      return false;
    }
  }

  Future<Map<String, dynamic>?> submit(String applicationId) async {
    try {
      final res = await _ds.submit(applicationId: applicationId);
      await loadList();
      return res;
    } catch (e) {
      // ignore: avoid_print
      print('[EmpInOffice] submit failed: ${ErrorHandler.handle(e).message}');
      return null;
    }
  }

  // Legacy bool wrapper
  Future<bool> submitBool(String applicationId) async => (await submit(applicationId)) != null;

  Future<Map<String, dynamic>?> getSchedulePreview({
    required double principal,
    required String frequency,
    int? termPeriods,
  }) async {
    try {
      return await _loanDs.getSchedulePreview(principal, frequency,
          termPeriods: termPeriods);
    } catch (_) {
      return null;
    }
  }

  bool get isLoading => state is AsyncLoading;
  List get items => (state.valueOrNull?['items'] as List?) ?? [];
}
