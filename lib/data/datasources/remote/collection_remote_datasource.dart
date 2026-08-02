// lib/data/datasources/remote/collection_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/collection_assignment_model.dart';

class CollectionRemoteDataSource {
  final DioClient _client;
  CollectionRemoteDataSource(this._client);

  Future<List<CollectionAssignmentModel>> getCollectionList({
    String? status,
    String? riderId,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.collectionsGetList,
      queryParams: {
        if (status != null) 'status': status,
        if (riderId != null) 'rider_id': riderId,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map(
          (e) => CollectionAssignmentModel.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<Map<String, dynamic>> getList({
    String? status,
    String? riderId,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.collectionsGetList,
      queryParams: {
        if (status != null) 'status': status,
        if (riderId != null) 'rider_id': riderId,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return {
      'items': list,
      'total': (res.data['total'] as num?)?.toInt() ?? list.length,
    };
  }

  Future<void> assign({
    required String loanScheduleId,
    required String riderId,
    String? collectionSchedule,
    String? notes,
  }) =>
      assignCollection(
        loanScheduleId: loanScheduleId,
        riderId: riderId,
        collectionSchedule: collectionSchedule,
        notes: notes,
      );

  Future<CollectionAssignmentModel> assignCollection({
    required String loanScheduleId,
    required String riderId,
    String? collectionSchedule,
    String? notes,
  }) async {
    final res = await _client.post(
      ApiEndpoints.collectionsAssign,
      data: {
        'loan_schedule_id': loanScheduleId,
        'rider_id': riderId,
        if (collectionSchedule != null)
          'collection_schedule': collectionSchedule,
        if (notes != null) 'notes': notes,
      },
    );
    return CollectionAssignmentModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> acceptCollection({required String assignmentId}) async {
    await _client.patch(
      ApiEndpoints.collectionsAccept,
      data: {'assignment_id': assignmentId},
    );
  }

  Future<void> declineCollection({required String assignmentId}) async {
    await _client.patch(
      ApiEndpoints.collectionsDecline,
      data: {'assignment_id': assignmentId},
    );
  }

  Future<void> recordCollection({
    required String assignmentId,
    required double amountCollected,
    String? notes,
    required String idempotencyKey,
  }) async {
    await _client.postWithIdempotency(
      ApiEndpoints.collectionsRecord,
      data: {
        'assignment_id': assignmentId,
        'amount_collected': amountCollected,
        if (notes != null) 'notes': notes,
      },
      idempotencyKey: idempotencyKey,
    );
  }

  Future<void> uploadProof({
    required String assignmentId,
    required List<Map<String, dynamic>> proofs,
  }) async {
    await _client.post(
      ApiEndpoints.collectionsUploadProof,
      data: {'assignment_id': assignmentId, 'proofs': proofs},
    );
  }
}
