// lib/presentation/features/head_manager/disbursements/providers/hm_disbursement_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/disbursement_remote_datasource.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmDisbursementState {
  final List<DisbursementModel> disbursements;
  final bool isLoading;
  final String? error;
  final String methodFilter;
  final String statusFilter;
  final String search;

  const HmDisbursementState({
    this.disbursements = const [],
    this.isLoading = false,
    this.error,
    this.methodFilter = 'all',
    this.statusFilter = 'all',
    this.search = '',
  });

  HmDisbursementState copyWith({
    List<DisbursementModel>? disbursements,
    bool? isLoading,
    String? error,
    String? methodFilter,
    String? statusFilter,
    String? search,
  }) =>
      HmDisbursementState(
        disbursements: disbursements ?? this.disbursements,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        methodFilter: methodFilter ?? this.methodFilter,
        statusFilter: statusFilter ?? this.statusFilter,
        search: search ?? this.search,
      );
}

class HmDisbursementNotifier extends StateNotifier<HmDisbursementState>
    with RealtimeRefreshMixin {
  final DisbursementRemoteDataSource _ds;

  HmDisbursementNotifier(this._ds) : super(const HmDisbursementState()) {
    bindRealtimeRefresh(['disbursements', 'loans'], refresh: load);
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _ds.getDisbursements(
        method: state.methodFilter == 'all' ? null : state.methodFilter,
        status: state.statusFilter == 'all' ? null : state.statusFilter,
      );
      state = state.copyWith(disbursements: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setMethod(String v) {
    state = state.copyWith(methodFilter: v);
    load();
  }

  void setStatus(String v) {
    state = state.copyWith(statusFilter: v);
    load();
  }

  void setSearch(String v) {
    state = state.copyWith(search: v);
    load();
  }

  Future<void> disburseGcash(
      {required String loanId, required String gcashNumber}) async {
    await _ds.disburseGcash(loanId: loanId, gcashNumber: gcashNumber);
    await load();
  }

  Future<void> disburseOfficeCash({required String loanId}) async {
    await _ds.disburseOfficeCash(loanId: loanId);
    await load();
  }

  Future<void> disburseRiderDelivery({
    required String loanId,
    required String riderId,
    String? deliveryDate,
    String? notes,
  }) async {
    await _ds.disburseRiderDelivery(
        loanId: loanId,
        riderId: riderId,
        deliveryDate: deliveryDate,
        notes: notes);
    await load();
  }
}

final hmDisbursementProvider =
    AutoDisposeStateNotifierProvider<HmDisbursementNotifier, HmDisbursementState>(
  (ref) => HmDisbursementNotifier(sl<DisbursementRemoteDataSource>()),
);
