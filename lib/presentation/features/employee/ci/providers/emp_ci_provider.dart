// lib/presentation/features/employee/ci/providers/emp_ci_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpCiState {
  final List<CreditInvestigationModel> items;
  final bool isLoading;
  final bool isLoadingDetail;
  final Map<String, dynamic>? detail;
  final String? error;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final String statusFilter;
  final String search;

  const EmpCiState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingDetail = false,
    this.detail,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.statusFilter = 'all',
    this.search = '',
  });

  EmpCiState copyWith({
    List<CreditInvestigationModel>? items,
    bool? isLoading,
    bool? isLoadingDetail,
    Map<String, dynamic>? detail,
    String? error,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    String? statusFilter,
    String? search,
  }) =>
      EmpCiState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isLoadingDetail: isLoadingDetail ?? this.isLoadingDetail,
        detail: detail ?? this.detail,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        totalCount: totalCount ?? this.totalCount,
        statusFilter: statusFilter ?? this.statusFilter,
        search: search ?? this.search,
      );
}

class EmpCiNotifier extends StateNotifier<EmpCiState>
    with RealtimeRefreshMixin {
  final CiRemoteDataSource _ds;
  final UserRemoteDataSource _userDs;

  EmpCiNotifier(this._ds, this._userDs) : super(const EmpCiState()) {
    bindRealtimeRefresh(['credit_investigations', 'ci_documents'],
        refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch({int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getList(
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        page: page,
      );
      final list = (res['data'] as List? ?? [])
          .map((e) =>
              CreditInvestigationModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        items: list,
        isLoading: false,
        currentPage: (meta['page'] as num?)?.toInt() ?? 1,
        totalPages: (meta['total_pages'] as num?)?.toInt() ?? 1,
        totalCount: (meta['total'] as num?)?.toInt() ?? list.length,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  // Keep legacy `load` alias for existing callers; delegates to fetch.
  Future<void> load(
      {String? status,
      String? riderId,
      int page = 1,
      bool silent = false}) async {
    if (status != null) {
      state = state.copyWith(statusFilter: status);
    }
    await fetch(page: page, silent: silent);
  }

  Future<void> loadDetails(String ciId) async {
    state = state.copyWith(isLoadingDetail: true, error: null);
    try {
      final detail = await _ds.getCiDetails(ciId);
      state = state.copyWith(
        isLoadingDetail: false,
        detail: detail,
      );
    } catch (e) {
      state = state.copyWith(
          isLoadingDetail: false,
          error: ErrorHandler.handle(e).message,
          detail: null);
    }
  }

  void setStatus(String s) {
    state = state.copyWith(statusFilter: s);
    fetch();
  }

  Future<bool> assignCi({
    required String loanId,
    required String riderId,
    required String notes,
    required String deadline,
  }) async {
    try {
      await _ds.assignCi(
        loanId: loanId,
        riderId: riderId,
        investigationNotes: notes.isEmpty ? null : notes,
        deadline: deadline.isEmpty ? null : deadline,
      );
      await fetch(page: state.currentPage);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> assign({
    required String loanId,
    required String riderId,
    String? notes,
    String? deadline,
  }) async {
    return assignCi(
      loanId: loanId,
      riderId: riderId,
      notes: notes ?? '',
      deadline: deadline ?? '',
    );
  }

  // Convenience wrapper matching HM's assignCI signature.
  Future<bool> assignCI({
    required String loanId,
    required String riderId,
    String notes = '',
    DateTime? deadline,
  }) {
    return assignCi(
      loanId: loanId,
      riderId: riderId,
      notes: notes,
      deadline: deadline?.toIso8601String() ?? '',
    );
  }

  Future<bool> approveReport({required String ciId, String? notes}) async {
    try {
      await _ds.approveCiReport(ciId: ciId, reviewNotes: notes);
      await fetch(page: state.currentPage);
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  Future<bool> rejectReport({required String ciId, required String reason}) async {
    try {
      await _ds.rejectCiReport(ciId: ciId, rejectionReason: reason);
      await fetch(page: state.currentPage);
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableRiders() async {
    try {
      final ds = _userDs;
      final res = await ds.getUserList(
        role: 'rider',
        status: 'active',
        page: 1,
        limit: 100,
      );
      final list =
          (res['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      return list;
    } catch (_) {
      try {
        return await _userDs.getAvailableRiders();
      } catch (_) {
        return [];
      }
    }
  }
}

final empCiProvider =
    AutoDisposeStateNotifierProvider<EmpCiNotifier, EmpCiState>((ref) {
  return EmpCiNotifier(sl<CiRemoteDataSource>(), sl<UserRemoteDataSource>());
});
