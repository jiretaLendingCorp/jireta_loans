// lib/data/repositories/collection_repository_impl.dart
import '../../domain/repositories/i_collection_repository.dart';
import '../datasources/remote/collection_remote_datasource.dart';

class CollectionRepositoryImpl implements ICollectionRepository {
  final CollectionRemoteDataSource _ds;
  CollectionRepositoryImpl(this._ds);

  @override
  Future<void> assignCollection(Map<String, dynamic> data) =>
      _ds.assignCollection(
        loanScheduleId:
            (data['loanScheduleId'] ?? data['loan_schedule_id'] ?? '')
                .toString(),
        riderId: (data['riderId'] ?? data['rider_id'] ?? '').toString(),
        collectionSchedule:
            (data['collectionSchedule'] ?? data['collection_schedule'] ??
                data['schedule'])
                as String?,
        notes: data['notes']?.toString(),
      );

  @override
  Future<void> acceptCollection(String assignmentId) =>
      _ds.acceptCollection(assignmentId: assignmentId);

  @override
  Future<void> declineCollection(String assignmentId) =>
      _ds.declineCollection(assignmentId: assignmentId);

  @override
  Future<void> recordCollection(Map<String, dynamic> data) =>
      _ds.recordCollection(
        assignmentId:
            (data['assignmentId'] ?? data['assignment_id'] ?? '').toString(),
        amountCollected: (data['amountCollected'] ?? data['amount_collected'] ?? 0)
            .toDouble(),
        notes: data['notes']?.toString(),
        idempotencyKey:
            (data['idempotencyKey'] ?? data['idempotency_key'] ?? '').toString(),
      );

  @override
  Future<void> uploadProof(
          String assignmentId, List<Map<String, dynamic>> files) =>
      _ds.uploadProof(assignmentId: assignmentId, proofs: files);

  @override
  Future<List<dynamic>> getCollectionList({String? status, int page = 1}) =>
      _ds.getCollectionList(status: status, page: page);
}
