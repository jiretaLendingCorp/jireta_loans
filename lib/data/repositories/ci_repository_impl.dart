// lib/data/repositories/ci_repository_impl.dart
import '../../domain/repositories/i_ci_repository.dart';
import '../datasources/remote/ci_remote_datasource.dart';

class CiRepositoryImpl implements ICiRepository {
  final CiRemoteDataSource _ds;
  CiRepositoryImpl(this._ds);

  @override
  Future<void> assignCi(Map<String, dynamic> data) => _ds.assignCi(
        loanId: (data['loanId'] ?? data['loan_id'] ?? '').toString(),
        riderId: (data['riderId'] ?? data['rider_id'] ?? '').toString(),
        investigationNotes:
            (data['investigationNotes'] ?? data['investigation_notes'] ??
                data['notes'])
                as String?,
        deadline: data['deadline']?.toString(),
      );

  @override
  Future<void> acceptCi(String ciId) => _ds.acceptCi(ciId: ciId);

  @override
  Future<void> declineCi(String ciId) => _ds.declineCi(ciId: ciId);

  @override
  Future<void> uploadCiDocuments(
          String ciId, List<Map<String, dynamic>> documents) =>
      _ds.uploadDocuments(ciId: ciId, docs: documents);

  @override
  Future<void> submitCiReport(String ciId, String reportSummary) =>
      _ds.submitReport(ciId: ciId, summary: reportSummary);

  @override
  Future<List<dynamic>> getCiList({String? status, int page = 1}) =>
      _ds.getCiList(status: status, page: page);
}
