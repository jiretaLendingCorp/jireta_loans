// lib/presentation/features/employee/ci/providers/emp_ci_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpCiState {
  final bool isLoading;
  final bool isLoadingDetail;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic>? detail;
  final String? error;
  final int total;

  const EmpCiState({
    this.isLoading = false,
    this.isLoadingDetail = false,
    this.items = const [],
    this.detail,
    this.error,
    this.total = 0,
  });

  EmpCiState copyWith({
    bool? isLoading,
    bool? isLoadingDetail,
    List<Map<String, dynamic>>? items,
    Map<String, dynamic>? detail,
    String? error,
    int? total,
  }) =>
      EmpCiState(
        isLoading: isLoading ?? this.isLoading,
        isLoadingDetail: isLoadingDetail ?? this.isLoadingDetail,
        items: items ?? this.items,
        detail: detail ?? this.detail,
        error: error,
        total: total ?? this.total,
      );
}

Map<String, dynamic> _ciModelToMap(CreditInvestigationModel m) => {
      'id': m.id,
      'loan_id': m.loanId,
      'rider_id': m.riderId,
      'assigned_by': m.assignedBy,
      'status': m.status,
      'investigation_notes': m.investigationNotes,
      'report_summary': m.reportSummary,
      'deadline': m.deadline?.toIso8601String(),
      'created_at': m.createdAt.toIso8601String(),
      'loan_number': m.loanNumber,
      'lender_name': m.lenderName,
      'rider_name': m.riderName,
      'assigned_by_name': m.assignedByName,
      'loan': m.loan,
      'rider': m.rider,
      'ci_documents': m.documents,
    };

class EmpCiNotifier extends StateNotifier<EmpCiState>
    with RealtimeRefreshMixin {
  final CiRemoteDataSource _ds;
  final UserRemoteDataSource _userDs;

  EmpCiNotifier(this._ds, this._userDs) : super(const EmpCiState()) {
    bindRealtimeRefresh(['credit_investigations', 'ci_documents'],
        refresh: () => load(silent: true));
  }

  Future<void> load({String? status, String? riderId, int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final list =
          await _ds.getCiList(status: status, riderId: riderId, page: page);
      state = state.copyWith(
        isLoading: false,
        items: list.map(_ciModelToMap).toList(),
        total: list.length,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message, items: []);
    }
  }

  Future<void> loadDetails(String ciId) async {
    state = state.copyWith(isLoadingDetail: true, error: null);
    try {
      final detail = await _ds.getCiDetails(ciId);
      state = state.copyWith(
        isLoadingDetail: false,
        detail: detail != null
            ? _ciModelToMap(CreditInvestigationModel.fromJson(detail))
            : null,
      );
    } catch (e) {
      state = state.copyWith(
          isLoadingDetail: false,
          error: ErrorHandler.handle(e).message,
          detail: null);
    }
  }

  Future<bool> assign({
    required String loanId,
    required String riderId,
    String? notes,
    String? deadline,
  }) async {
    try {
      await _ds.assignCi(
        loanId: loanId,
        riderId: riderId,
        investigationNotes: notes,
        deadline: deadline,
      );
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableRiders() async {
    try {
      final data = await _userDs.getList(
        role: 'rider',
        status: 'active',
        page: 1,
        limit: 100,
      );
      return List<Map<String, dynamic>>.from(data['items'] ?? []);
    } catch (_) {
      return [];
    }
  }
}

final empCiProvider =
    AutoDisposeStateNotifierProvider<EmpCiNotifier, EmpCiState>((ref) {
  return EmpCiNotifier(sl<CiRemoteDataSource>(), sl<UserRemoteDataSource>());
});
