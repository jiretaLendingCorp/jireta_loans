// lib/presentation/features/employee/loans/providers/emp_loan_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpLoanState {
  final List<LoanModel> loans;
  final bool isLoading;
  final String? error;
  final int page;
  final int totalPages;
  final int total;
  final String search;
  final String? statusFilter;
  final String? dateFrom;
  final String? dateTo;

  const EmpLoanState({
    this.loans = const [],
    this.isLoading = false,
    this.error,
    this.page = 1,
    this.totalPages = 1,
    this.total = 0,
    this.search = '',
    this.statusFilter,
    this.dateFrom,
    this.dateTo,
  });

  static const _unset = Object();

  EmpLoanState copyWith({
    List<LoanModel>? loans,
    bool? isLoading,
    String? error,
    int? page,
    int? totalPages,
    int? total,
    String? search,
    Object? statusFilter = _unset,
    String? dateFrom,
    String? dateTo,
  }) =>
      EmpLoanState(
        loans: loans ?? this.loans,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        total: total ?? this.total,
        search: search ?? this.search,
        statusFilter: statusFilter == _unset
            ? this.statusFilter
            : statusFilter as String?,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );
}

class EmpLoanNotifier extends StateNotifier<EmpLoanState>
    with RealtimeRefreshMixin {
  final LoanRemoteDataSource _ds;
  EmpLoanNotifier(this._ds) : super(const EmpLoanState()) {
    bindRealtimeRefresh(['loans', 'loan_schedules'], refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false, int? page}) async {
    final targetPage = page ?? state.page;
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getList(
        status: state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: targetPage,
        limit: 10,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      final loans = (res['data'] as List? ?? [])
          .map((e) => LoanModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        loans: loans,
        isLoading: false,
        page: meta['page'] as int? ?? targetPage,
        totalPages: meta['total_pages'] as int? ?? 1,
        total: meta['total'] as int? ?? loans.length,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setPage(int page) {
    state = state.copyWith(page: page);
    load();
  }

  void setSearch(String v) {
    state = state.copyWith(search: v, page: 1);
    load();
  }

  void setStatus(String? v) {
    state = state.copyWith(statusFilter: v, page: 1);
    load();
  }

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to, page: 1);
    load();
  }

  Future<LoanModel> getDetails(String loanId) async {
    return await _ds.getLoanDetails(loanId);
  }

  Future<void> approveLoan(String loanId) async {
    await _ds.approveLoan(loanId);
    await load();
  }

  Future<void> rejectLoan(String loanId, String reason) async {
    await _ds.rejectLoan(loanId, reason);
    await load();
  }

  Future<void> requestCi(String loanId) async {
    await _ds.requestCi(loanId);
    await load();
  }
}

// Extension for additional emp loan actions (added methods to existing notifier)
extension EmpLoanProviderExtension on EmpLoanNotifier {
  Future<bool> approve(String loanId) async {
    try {
      await _ds.approveLoan(loanId);
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reject(String loanId, String reason) async {
    try {
      await _ds.rejectLoan(loanId, reason);
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestCI(String loanId) async {
    await _ds.requestCi(loanId);
    await load();
  }

  Future<void> cancel(String loanId) async {
    await _ds.cancelLoan(loanId);
    await load();
  }
}

final empLoanProvider =
    AutoDisposeStateNotifierProvider<EmpLoanNotifier, EmpLoanState>(
  (ref) => EmpLoanNotifier(sl<LoanRemoteDataSource>()),
);
