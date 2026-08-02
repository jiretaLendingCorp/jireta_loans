// lib/domain/repositories/i_in_office_repository.dart
abstract class IInOfficeRepository {
  Future<Map<String, dynamic>> createDraft();
  Future<void> saveStep(
      String applicationId, int step, Map<String, dynamic> data);
  Future<void> submitApplication(String applicationId);
  Future<List<dynamic>> getInOfficeList({String? status, int page});
}
