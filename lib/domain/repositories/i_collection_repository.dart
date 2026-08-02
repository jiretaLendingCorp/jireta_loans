// lib/domain/repositories/i_collection_repository.dart
abstract class ICollectionRepository {
  Future<void> assignCollection(Map<String, dynamic> data);
  Future<void> acceptCollection(String assignmentId);
  Future<void> declineCollection(String assignmentId);
  Future<void> recordCollection(Map<String, dynamic> data);
  Future<void> uploadProof(
      String assignmentId, List<Map<String, dynamic>> files);
  Future<List<dynamic>> getCollectionList({String? status, int page});
}
