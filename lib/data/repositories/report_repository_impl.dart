// lib/data/repositories/report_repository_impl.dart
import '../../domain/repositories/i_report_repository.dart';
import '../datasources/remote/report_remote_datasource.dart';

class ReportRepositoryImpl implements IReportRepository {
  final ReportRemoteDataSource _ds;
  ReportRepositoryImpl(this._ds);

  @override
  Future<void> generateReport(
      String templateKey, Map<String, dynamic> parameters) async {
    await _ds.generateReport(
      templateKey: templateKey,
      parameters: parameters,
      format: 'pdf',
    );
  }

  @override
  Future<List<dynamic>> getReportList() => _ds.getReportList();

  @override
  Future<List<dynamic>> getReportHistory({int page = 1}) =>
      _ds.getReportHistory(page: page);
}
