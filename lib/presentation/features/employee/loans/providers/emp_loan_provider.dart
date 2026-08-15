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
  final String search;
  final String? statusFilter;

  const EmpLoanState({
    this.loans = const [],
    this.isLoading = false,
    this.error,
    this.page = 1,
    this.search = '',
    this.statusFilter,
  });

  EmpLoanState copyWith({
    List<LoanModel>? loans,
    bool? isLoading,
    String? error,
    int? page,
    String? search,
    String? statusFilter,
  }) =>
      EmpLoanState(
        loans: loans ?? this.loans,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        page: page ?? this.page,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
      );
}

class EmpLoanNotifier extends StateNotifier<EmpLoanState>
    with RealtimeRefreshMixin {
  final LoanRemoteDataSource _ds;
  EmpLoanNotifier(this._ds) : super(const EmpLoanState()) {
    bindRealtimeRefresh(['loans', 'loan_schedules'], refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final list = await _ds.getLoanList(
        status: state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: state.page,
      );
      state = state.copyWith(loans: list, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setSearch(String v) {
    state = state.copyWith(search: v, page: 1);
    load();
  }

  void setStatus(String? v) {
    state = state.copyWith(statusFilter: v, page: 1);
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
