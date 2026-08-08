// lib/presentation/features/employee/in_office/providers/emp_in_office_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/in_office_remote_datasource.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

final empInOfficeProvider = StateNotifierProvider<EmpInOfficeNotifier,
    AsyncValue<Map<String, dynamic>>>((ref) {
  return EmpInOfficeNotifier(
      sl<InOfficeRemoteDataSource>(), sl<LoanRemoteDataSource>());
});

class EmpInOfficeNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>>
    with RealtimeRefreshMixin {
  final InOfficeRemoteDataSource _ds;
  final LoanRemoteDataSource _loanDs;

  EmpInOfficeNotifier(this._ds, this._loanDs)
      : super(const AsyncData({'items': [], 'total': 0})) {
    bindRealtimeRefresh(['in_office_applications'], refresh: loadList);
    loadList();
  }

  Future<void> loadList({String? status, int page = 1}) async {
    state = const AsyncLoading();
    try {
      final data = await _ds.getList(
          status: status == 'all' ? null : status, page: page);
      state = AsyncData({'items': data, 'total': data.length});
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  void setStatus(String status) => loadList(status: status);

  Future<String?> createDraft() async {
    try {
      final data = await _ds.createDraft();
      return data['application_id'] as String?;
    } catch (_) {
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
    } catch (_) {
      return false;
    }
  }

  Future<bool> submit(String applicationId) async {
    try {
      await _ds.submit(applicationId: applicationId);
      await loadList();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getSchedulePreview({
    required double principal,
    required String frequency,
  }) async {
    try {
      return await _loanDs.getSchedulePreview(principal, frequency);
    } catch (_) {
      return null;
    }
  }

  bool get isLoading => state is AsyncLoading;
  List get items => (state.valueOrNull?['items'] as List?) ?? [];
}
