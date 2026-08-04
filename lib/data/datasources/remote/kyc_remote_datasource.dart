// lib/data/datasources/remote/kyc_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/kyc_document_model.dart';

class KycRemoteDataSource {
  final DioClient _client;
  KycRemoteDataSource(this._client);

  Future<Map<String, dynamic>> getKycList({
    String? status,
    String? lenderName,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.kycGetList,
      queryParams: {
        if (status != null) 'status': status,
        if (lenderName != null) 'lender_name': lenderName,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    final total = (res.data['total'] as num?)?.toInt() ?? list.length;
    final totalPages =
        (res.data['totalPages'] as num?)?.toInt() ??
        (limit == 0 ? 1 : (total / limit).ceil());
    return {
      'data': list,
      'meta': {'page': page, 'total_pages': totalPages, 'total': total},
    };
  }

  Future<Map<String, dynamic>> getList({
    String? status,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.kycGetList,
      queryParams: {
        if (status != null) 'status': status,
        if (search != null) 'lender_name': search,
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

  Future<KycStatusModel> getKycStatus() async {
    final res = await _client.get(ApiEndpoints.kycGetStatus);
    return KycStatusModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<KycDocumentModel> getKycDetails({required String kycDocId}) async {
    final res = await _client.get(
      ApiEndpoints.kycGetDetails,
      queryParams: {'kyc_doc_id': kycDocId},
    );
    return KycDocumentModel.fromJson(
      (res.data as Map<String, dynamic>)['document'] as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>?> getStatus({required String lenderId}) async {
    final res = await _client.get(
      ApiEndpoints.kycGetStatus,
      queryParams: {'lender_id': lenderId},
    );
    return res.data as Map<String, dynamic>?;
  }

  Future<void> verifyKyc({
    required String kycDocId,
    required String action,
    String? rejectionNotes,
  }) async {
    await _client.patch(
      ApiEndpoints.kycVerify,
      data: {
        'kyc_doc_id': kycDocId,
        'action': action,
        if (rejectionNotes != null) 'rejection_notes': rejectionNotes,
      },
    );
  }

  Future<void> verify({
    required String kycDocId,
    required String action,
    String? rejectionNotes,
  }) =>
      verifyKyc(
        kycDocId: kycDocId,
        action: action,
        rejectionNotes: rejectionNotes,
      );

  Future<void> submitKyc(List<Map<String, dynamic>> documents) async {
    await _client.post(ApiEndpoints.kycSubmit, data: {'documents': documents});
  }
}
