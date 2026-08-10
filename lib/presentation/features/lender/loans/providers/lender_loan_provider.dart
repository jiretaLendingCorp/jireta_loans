// lib/presentation/features/lender/loans/providers/lender_loan_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class LenderLoanState {
  final List<LoanModel> loans;
  final LoanModel? activeLoan;
  final LoanModel? selectedLoan;
  final Map<String, dynamic>? schedulePreview;
  final bool isLoading;
  final String? error;
  final bool isSubmitting;

  const LenderLoanState({
    this.loans = const [],
    this.activeLoan,
    this.selectedLoan,
    this.schedulePreview,
    this.isLoading = false,
    this.error,
    this.isSubmitting = false,
  });

  LenderLoanState copyWith({
    List<LoanModel>? loans,
    LoanModel? activeLoan,
    LoanModel? selectedLoan,
    Map<String, dynamic>? schedulePreview,
    bool? isLoading,
    String? error,
    bool? isSubmitting,
  }) =>
      LenderLoanState(
        loans: loans ?? this.loans,
        activeLoan: activeLoan ?? this.activeLoan,
        selectedLoan: selectedLoan ?? this.selectedLoan,
        schedulePreview: schedulePreview ?? this.schedulePreview,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );
}

class LenderLoanNotifier extends StateNotifier<LenderLoanState>
    with RealtimeRefreshMixin {
  final LoanRemoteDataSource _ds;

  LenderLoanNotifier(this._ds) : super(const LenderLoanState()) {
    bindRealtimeRefresh(['loans', 'loan_schedules'], refresh: loadLoans);
    loadLoans();
  }

  Future<void> loadLoans() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final loans = await _ds.getLoanList(page: 1);
      // Active Loan also surfaces approved-but-not-yet-released loans.
      // Prefer a real active/overdue loan over an approved one.
      LoanModel? active;
      for (final s in ['active', 'overdue', 'approved']) {
        active = loans.where((l) => l.status == s).firstOrNull;
        if (active != null) break;
      }
      state =
          state.copyWith(loans: loans, activeLoan: active, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadLoanDetails(String loanId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final loan = await _ds.getLoanDetails(loanId);
      state = state.copyWith(selectedLoan: loan, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> getSchedulePreview({
    required double amount,
    required String frequency,
  }) async {
    try {
      final preview = await _ds.getSchedulePreview(amount, frequency);
      state = state.copyWith(schedulePreview: preview);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<bool> applyLoan({
    required double amount,
    required String frequency,
    required String purpose,
    Map<String, dynamic>? coMaker,
    Map<String, dynamic>? disbursement,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _ds.applyLoan(
        amount: amount,
        frequency: frequency,
        purpose: purpose,
        coMaker: coMaker,
        disbursement: disbursement,
      );
      state = state.copyWith(isSubmitting: false);
      await loadLoans();
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  Future<bool> cancelLoan(String loanId) async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _ds.cancelLoan(loanId);
      state = state.copyWith(isSubmitting: false);
      await loadLoans();
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  Future<void> refresh() => loadLoans();
}

final lenderLoanProvider =
    AutoDisposeStateNotifierProvider<LenderLoanNotifier, LenderLoanState>((ref) {
  return LenderLoanNotifier(sl<LoanRemoteDataSource>());
});
