// lib/domain/repositories/i_ci_repository.dart
abstract class ICiRepository {
  Future<void> assignCi(Map<String, dynamic> data);
  Future<void> acceptCi(String ciId);
  Future<void> declineCi(String ciId);
  Future<void> uploadCiDocuments(
      String ciId, List<Map<String, dynamic>> documents);
  Future<void> submitCiReport(String ciId, String reportSummary);
  Future<List<dynamic>> getCiList({String? status, int page});
}
