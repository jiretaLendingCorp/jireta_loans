// lib/data/datasources/remote/ci_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/credit_investigation_model.dart';

class CiRemoteDataSource {
  final DioClient _client;
  CiRemoteDataSource(this._client);

  Future<List<CreditInvestigationModel>> getCiList({
    String? status,
    String? riderId,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.ciGetList,
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
            (e) => CreditInvestigationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>?> getCiDetails(String ciId) async {
    try {
      final res = await _client.get(
        ApiEndpoints.ciGetList,
        queryParams: {'ci_id': ciId, 'limit': 1},
      );
      final data = res.data;
      if (data is Map<String, dynamic> && data.containsKey('id')) return data;
      final list = (data['data'] as List?);
      if (list != null && list.isNotEmpty) {
        return list.first as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<CreditInvestigationModel> assignCi({
    required String loanId,
    required String riderId,
    String? investigationNotes,
    String? deadline,
  }) async {
    final res = await _client.post(
      ApiEndpoints.ciAssign,
      data: {
        'loan_id': loanId,
        'rider_id': riderId,
        if (investigationNotes != null)
          'investigation_notes': investigationNotes,
        if (deadline != null) 'deadline': deadline,
      },
    );
    return CreditInvestigationModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> acceptCi({required String ciId}) async {
    await _client.patch(ApiEndpoints.ciAccept, data: {'ci_id': ciId});
  }

  Future<void> declineCi({required String ciId}) async {
    await _client.patch(ApiEndpoints.ciDecline, data: {'ci_id': ciId});
  }

  Future<void> submitCiReport({
    required String ciId,
    required String reportSummary,
  }) async {
    await _client.post(
      ApiEndpoints.ciSubmitReport,
      data: {'ci_id': ciId, 'report_summary': reportSummary},
    );
  }

  /// Manager approves a submitted CI report (completed -> approved)
  Future<void> approveCiReport({
    required String ciId,
    String? reviewNotes,
  }) async {
    await _client.post(
      ApiEndpoints.ciApproveReport,
      data: {'ci_id': ciId, if (reviewNotes != null) 'review_notes': reviewNotes},
    );
  }

  /// Manager rejects a submitted CI report (completed -> rejected)
  Future<void> rejectCiReport({
    required String ciId,
    required String rejectionReason,
  }) async {
    await _client.post(
      ApiEndpoints.ciRejectReport,
      data: {'ci_id': ciId, 'rejection_reason': rejectionReason},
    );
  }

  // Aliases for HM/Employee providers to call without patch vs post confusion
  Future<void> approveReport({required String ciId, String? notes}) =>
      approveCiReport(ciId: ciId, reviewNotes: notes);
  Future<void> rejectReport({required String ciId, required String reason}) =>
      rejectCiReport(ciId: ciId, rejectionReason: reason);

  Future<Map<String, dynamic>> getList({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.ciGetList,
      queryParams: {
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

  Future<void> submitReport({
    required String ciId,
    required String summary,
  }) =>
      submitCiReport(ciId: ciId, reportSummary: summary);

  Future<void> uploadDocuments({
    required String ciId,
    required List<Map<String, dynamic>> docs,
  }) async {
    await _client.post(
      ApiEndpoints.ciUploadDocuments,
      data: {'ci_id': ciId, 'documents': docs},
    );
  }
}
