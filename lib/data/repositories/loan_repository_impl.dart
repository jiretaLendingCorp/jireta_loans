// lib/data/repositories/loan_repository_impl.dart
import '../../domain/repositories/i_loan_repository.dart';
import '../datasources/remote/loan_remote_datasource.dart';
import '../models/loan_model.dart';

class LoanRepositoryImpl implements ILoanRepository {
  final LoanRemoteDataSource _ds;
  LoanRepositoryImpl(this._ds);

  @override
  Future<void> applyLoan(Map<String, dynamic> data) => _ds.applyLoan(
        amount: (data['amount'] ?? data['principal_amount'] ?? 0).toDouble(),
        frequency: (data['frequency'] ?? 'monthly').toString(),
        purpose: (data['purpose'] ?? '').toString(),
      );

  @override
  Future<void> approveLoan(String loanId) => _ds.approveLoan(loanId);

  @override
  Future<void> rejectLoan(String loanId, String reason) =>
      _ds.rejectLoan(loanId, reason);

  @override
  Future<void> cancelLoan(String loanId) => _ds.cancelLoan(loanId);

  @override
  Future<List<dynamic>> getLoanList(
          {String? status, int page = 1, String? search}) =>
      _ds.getLoanList(status: status, page: page, search: search);

  @override
  Future<LoanModel> getLoanDetails(String loanId) =>
      _ds.getLoanDetails(loanId);

  @override
  Future<Map<String, dynamic>> getSchedulePreview(
          {required double principal, required String frequency}) =>
      _ds.getSchedulePreview(principal, frequency);

  @override
  Future<void> applyPenalty(String loanId) => _ds.applyPenalty(loanId);

  @override
  Future<void> requestCi(String loanId) => _ds.requestCi(loanId);
}
