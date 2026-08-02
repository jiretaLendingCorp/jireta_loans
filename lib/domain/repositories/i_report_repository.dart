// lib/domain/repositories/i_report_repository.dart
abstract class IReportRepository {
  Future<void> generateReport(
      String templateKey, Map<String, dynamic> parameters);
  Future<List<dynamic>> getReportList();
  Future<List<dynamic>> getReportHistory({int page});
}
