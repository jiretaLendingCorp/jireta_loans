// lib/data/datasources/remote/payment_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/payment_model.dart';

class PaymentRemoteDataSource {
  final DioClient _client;
  PaymentRemoteDataSource(this._client);

  Future<List<PaymentModel>> getPaymentList({
    String? method,
    String? status,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.paymentsGetList,
      queryParams: {
        if (method != null) 'method': method,
        if (status != null) 'status': status,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map((e) => PaymentModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> recordOfficePayment({
    required String loanId,
    required String loanScheduleId,
    required double amount,
    String? notes,
    String? assignmentId,
    required String idempotencyKey,
  }) async {
    final res = await _client.postWithIdempotency(
      ApiEndpoints.paymentsRecordOffice,
      data: {
        'loan_id': loanId,
        'loan_schedule_id': loanScheduleId,
        'amount': amount,
        if (notes != null) 'notes': notes,
        if (assignmentId != null) 'assignment_id': assignmentId,
      },
      idempotencyKey: idempotencyKey,
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> generateXenditLink({
    required String loanId,
    required String loanScheduleId,
  }) async {
    final res = await _client.post(
      ApiEndpoints.paymentsGenerateXenditLink,
      data: {'loan_id': loanId, 'loan_schedule_id': loanScheduleId},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<void> reversePayment({
    required String paymentId,
    required String reason,
  }) async {
    await _client.patch(
      ApiEndpoints.paymentsReverse,
      data: {'payment_id': paymentId, 'reason': reason},
    );
  }

  Future<String?> getReceipt({required String paymentId}) async {
    final res = await _client.get(
      ApiEndpoints.paymentsGetReceipt,
      queryParams: {'payment_id': paymentId},
    );
    return res.data['signed_url'] as String?;
  }

  Future<Map<String, dynamic>> getList({
    String? method,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.paymentsGetList,
      queryParams: {
        if (method != null) 'method': method,
        if (status != null) 'status': status,
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

  Future<Map<String, dynamic>> getPaymentListPage({
    String? method,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.paymentsGetList,
      queryParams: {
        if (method != null) 'method': method,
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    final total = (res.data['total'] as num?)?.toInt() ?? list.length;
    final totalPages = (res.data['totalPages'] as num?)?.toInt() ??
        (limit == 0 ? 1 : (total / limit).ceil());
    return {
      'data': list,
      'meta': {'page': page, 'total_pages': totalPages, 'total': total},
    };
  }

  Future<PaymentModel> getPaymentDetail(String paymentId) async {
    final res = await _client.get(
      ApiEndpoints.paymentsGetList,
      queryParams: {'payment_id': paymentId, 'limit': 1},
    );
    final data = res.data;
    if (data is Map<String, dynamic> && data.containsKey('id')) {
      return PaymentModel.fromJson(data);
    }
    final list = (data['data'] as List?);
    if (list != null && list.isNotEmpty) {
      return PaymentModel.fromJson(list.first as Map<String, dynamic>);
    }
    throw Exception('Payment not found');
  }

  Future<void> reverse({
    required String paymentId,
    required String reason,
  }) =>
      reversePayment(paymentId: paymentId, reason: reason);

  Future<Map<String, dynamic>> recordOffice({
    required String loanId,
    required String loanScheduleId,
    required double amount,
    String? notes,
    String? assignmentId,
    required String idempotencyKey,
  }) =>
      recordOfficePayment(
        loanId: loanId,
        loanScheduleId: loanScheduleId,
        amount: amount,
        notes: notes,
        assignmentId: assignmentId,
        idempotencyKey: idempotencyKey,
      );
}
