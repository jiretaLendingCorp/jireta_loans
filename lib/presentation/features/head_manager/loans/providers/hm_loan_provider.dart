// lib/presentation/features/head_manager/loans/providers/hm_loan_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmLoanState {
  final List<LoanModel> loans;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  final String statusFilter;
  final String search;
  final String tabFilter;

  const HmLoanState({
    this.loans = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.statusFilter = 'all',
    this.search = '',
    this.tabFilter = 'all',
  });

  HmLoanState copyWith({
    List<LoanModel>? loans,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    String? statusFilter,
    String? search,
    String? tabFilter,
  }) =>
      HmLoanState(
        loans: loans ?? this.loans,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        statusFilter: statusFilter ?? this.statusFilter,
        search: search ?? this.search,
        tabFilter: tabFilter ?? this.tabFilter,
      );
}

class HmLoanNotifier extends StateNotifier<HmLoanState>
    with RealtimeRefreshMixin {
  final LoanRemoteDataSource _ds;

  HmLoanNotifier(this._ds) : super(const HmLoanState()) {
    bindRealtimeRefresh(['loans', 'loan_schedules'], refresh: fetchLoans);
    fetchLoans();
  }

  Future<void> fetchLoans({int page = 1}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getList(
        page: page,
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
      );
      final loans = (res['data'] as List? ?? [])
          .map((e) => LoanModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        loans: loans,
        isLoading: false,
        currentPage: meta['page'] as int? ?? 1,
        totalPages: meta['total_pages'] as int? ?? 1,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setStatus(String status) {
    state = state.copyWith(statusFilter: status);
    fetchLoans();
  }

  void setSearch(String q) {
    state = state.copyWith(search: q);
    fetchLoans();
  }

  void setTab(String tab) {
    state = state.copyWith(
        tabFilter: tab, statusFilter: tab == 'all' ? 'all' : tab);
    fetchLoans();
  }

  Future<Map<String, dynamic>?> getLoanDetails(String loanId) async {
    try {
      return await _ds.getDetails(loanId: loanId);
    } catch (_) {
      return null;
    }
  }

  Future<bool> approveLoan(String loanId) async {
    try {
      await _ds.approveLoan(loanId);
      await fetchLoans();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rejectLoan(String loanId, String reason) async {
    try {
      await _ds.rejectLoan(loanId, reason);
      await fetchLoans();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelLoan(String loanId) async {
    try {
      await _ds.cancelLoan(loanId);
      await fetchLoans();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestCi(String loanId) async {
    try {
      await _ds.requestCi(loanId);
      await fetchLoans();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> applyPenalty(String loanId) async {
    try {
      await _ds.applyPenalty(loanId);
      await fetchLoans();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getSchedulePreview(
      double principal, String frequency) async {
    try {
      return await _ds.getSchedulePreview(principal, frequency);
    } catch (_) {
      return null;
    }
  }
}

final hmLoanProvider =
    StateNotifierProvider<HmLoanNotifier, HmLoanState>((ref) {
  return HmLoanNotifier(sl<LoanRemoteDataSource>());
});
