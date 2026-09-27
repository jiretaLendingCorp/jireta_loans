// lib/domain/repositories/i_loan_repository.dart
import '../../data/models/loan_model.dart';

abstract class ILoanRepository {
  Future<void> applyLoan(Map<String, dynamic> data);
  Future<void> approveLoan(String loanId);
  /// [reapplyAllowedAt] — 00176: kailan pwedeng mag-apply ulit ang lender
  /// (pinili ng staff sa reject modal). Null = server-side 1-month default.
  Future<void> rejectLoan(String loanId, String reason,
      {DateTime? reapplyAllowedAt});
  Future<void> cancelLoan(String loanId);
  Future<List<dynamic>> getLoanList({String? status, int page, String? search});
  Future<LoanModel> getLoanDetails(String loanId);
  Future<Map<String, dynamic>> getSchedulePreview(
      {required double principal, required String frequency});
  Future<void> applyPenalty(String loanId);
  Future<void> requestCi(String loanId);
}
