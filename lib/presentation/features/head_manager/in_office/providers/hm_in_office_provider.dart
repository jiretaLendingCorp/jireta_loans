// lib/presentation/features/head_manager/in_office/providers/hm_in_office_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
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
    StateNotifierProvider<HmInOfficeNotifier, HmInOfficeState>((ref) {
  return HmInOfficeNotifier(
      sl<InOfficeRemoteDataSource>(), sl<LoanRemoteDataSource>());
});

class HmInOfficeNotifier extends StateNotifier<HmInOfficeState>
    with RealtimeRefreshMixin {
  final InOfficeRemoteDataSource _ds;
  final LoanRemoteDataSource _loanDs;
  HmInOfficeNotifier(this._ds, this._loanDs)
      : super(const HmInOfficeState()) {
    bindRealtimeRefresh(['in_office_applications'], refresh: load);
    load();
  }

  Future<void> load({String? status, int page = 1}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _ds.getList(
        status: status == 'all' ? null : status,
        page: page,
      );
      state = state.copyWith(applications: data, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setStatus(String status) => load(status: status);

  Future<String?> createDraft() async {
    try {
      final data = await _ds.createDraft();
      return data['application_id'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<bool> saveStep(
      String applicationId, int step, Map<String, dynamic> data) async {
    try {
      await _ds.saveStep(applicationId: applicationId, step: step, data: data);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> submitApplication(String applicationId) async {
    try {
      await _ds.submit(applicationId: applicationId);
      await load();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getSchedulePreview(
      double principal, String frequency) async {
    try {
      return await _loanDs.getSchedulePreview(principal, frequency);
    } catch (e) {
      return null;
    }
  }
}
