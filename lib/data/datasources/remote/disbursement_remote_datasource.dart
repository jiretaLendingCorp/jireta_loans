// lib/data/datasources/remote/disbursement_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/disbursement_model.dart';

class DisbursementRemoteDataSource {
  final DioClient _client;
  DisbursementRemoteDataSource(this._client);

  Future<List<DisbursementModel>> getDisbursementList({
    String? method,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.disbursementsGetList,
      queryParams: {
        if (method != null) 'method': method,
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map((e) => DisbursementModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> disburseViaGcash({
    required String loanId,
    required String gcashNumber,
  }) async {
    final res = await _client.post(
      ApiEndpoints.disbursementsGcash,
      data: {'loan_id': loanId, 'gcash_number': gcashNumber},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<void> disburseOfficeCash({
    required String loanId,
    String? notes,
  }) async {
    await _client.post(
      ApiEndpoints.disbursementsOfficeCash,
      data: {'loan_id': loanId, if (notes != null) 'notes': notes},
    );
  }

  Future<void> disburseViaRider({
    required String loanId,
    required String riderId,
    required String deliveryDate,
    String? notes,
  }) async {
    await _client.post(
      ApiEndpoints.disbursementsRiderDelivery,
      data: {
        'loan_id': loanId,
        'rider_id': riderId,
        'delivery_date': deliveryDate,
        if (notes != null) 'notes': notes,
      },
    );
  }

  Future<List<DisbursementModel>> getDisbursements({
    String? method,
    String? status,
    int page = 1,
    int limit = 20,
  }) =>
      getDisbursementList(method: method, status: status, page: page, limit: limit);

  Future<Map<String, dynamic>> disburseGcash({
    required String loanId,
    required String gcashNumber,
  }) =>
      disburseViaGcash(loanId: loanId, gcashNumber: gcashNumber);

  Future<void> disburseRiderDelivery({
    required String loanId,
    required String riderId,
    String? deliveryDate,
    String? notes,
  }) =>
      disburseViaRider(
        loanId: loanId,
        riderId: riderId,
        deliveryDate: deliveryDate ?? '',
        notes: notes,
      );

  Future<DisbursementModel?> getDisbursementDetail(String disbursementId) async {
    try {
      final res = await _client.get(
        ApiEndpoints.disbursementsGetList,
        queryParams: {'disbursement_id': disbursementId, 'limit': 1},
      );
      final data = res.data;
      if (data is Map<String, dynamic> && data.containsKey('id')) {
        return DisbursementModel.fromJson(data);
      }
      final list = (data['data'] as List?);
      if (list != null && list.isNotEmpty) {
        return DisbursementModel.fromJson(list.first as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
