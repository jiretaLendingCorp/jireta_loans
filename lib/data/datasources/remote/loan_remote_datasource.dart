// lib/data/datasources/remote/loan_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/loan_model.dart';
import '../../models/penalty_log_model.dart';

class LoanRemoteDataSource {
  final DioClient _client;
  LoanRemoteDataSource(this._client);

  Future<Map<String, dynamic>> applyLoan({
    required double amount,
    required String frequency,
    required String purpose,
    Map<String, dynamic>? coMaker,
    Map<String, dynamic>? disbursement,
    int? termPeriods,
  }) async {
    final res = await _client.post(
      ApiEndpoints.loansApply,
      data: {
        'principal_amount': amount,
        'frequency': frequency,
        'purpose': purpose,
        if (termPeriods != null) 'term_periods': termPeriods,
        if (coMaker != null) 'co_maker': coMaker,
        if (disbursement != null) 'disbursement': disbursement,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<List<LoanModel>> getLoanList({
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    String? lenderId,
  }) async {
    final res = await _client.get(
      ApiEndpoints.loansGetList,
      queryParams: {
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
        if (search != null) 'search': search,
        if (lenderId != null) 'lender_id': lenderId,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map((e) => LoanModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getList({
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    String? lenderId,
  }) async {
    final res = await _client.get(
      ApiEndpoints.loansGetList,
      queryParams: {
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
        if (search != null) 'search': search,
        if (lenderId != null) 'lender_id': lenderId,
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

  Future<LoanModel> getLoanDetails(String loanId) async {
    final res = await _client.get(
      ApiEndpoints.loansGetDetails,
      queryParams: {'loan_id': loanId},
    );
    return LoanModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getSchedulePreview(
      double principal, String frequency,
      {int? termPeriods}) async {
    final res = await _client.post(
      ApiEndpoints.loansGetSchedulePreview,
      data: {
        'principal': principal,
        'frequency': frequency,
        if (termPeriods != null) 'term_periods': termPeriods,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDetails({required String loanId}) async {
    final res = await _client.get(
      ApiEndpoints.loansGetDetails,
      queryParams: {'loan_id': loanId},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<void> approveLoan(String loanId) async {
    await _client.patch(ApiEndpoints.loansApprove, data: {'loan_id': loanId});
  }

  Future<void> rejectLoan(String loanId, String reason) async {
    await _client.patch(
      ApiEndpoints.loansReject,
      data: {'loan_id': loanId, 'rejection_reason': reason},
    );
  }

  Future<void> cancelLoan(String loanId) async {
    await _client.patch(ApiEndpoints.loansCancel, data: {'loan_id': loanId});
  }

  Future<void> requestCi(String loanId) async {
    await _client.patch(ApiEndpoints.loansRequestCi, data: {'loan_id': loanId});
  }

  Future<void> applyPenalty(String loanId) async {
    await _client.post(
      ApiEndpoints.loansApplyPenalty,
      data: {'loan_id': loanId},
    );
  }

  Future<List<PenaltyLogModel>> getPenaltyLogs(
      {int page = 1, int limit = 50}) async {
    try {
      final res = await _client.get(
        ApiEndpoints.loansGetList,
        queryParams: {'include_penalties': true, 'page': page, 'limit': limit},
      );
      final list = (res.data['penalty_logs'] as List?) ?? [];
      return list
          .map((e) => PenaltyLogModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
