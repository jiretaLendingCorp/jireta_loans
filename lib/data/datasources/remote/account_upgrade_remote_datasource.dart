// lib/data/datasources/remote/account_upgrade_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/account_upgrade_document_model.dart';

class AccountUpgradeRemoteDataSource {
  final DioClient _client;
  AccountUpgradeRemoteDataSource(this._client);

  Future<Map<String, dynamic>> accountUpgradeGetList({
    String? status,
    String? lenderName,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.accountUpgradeGetList,
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
    final totalPages = (res.data['totalPages'] as num?)?.toInt() ??
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
      ApiEndpoints.accountUpgradeGetList,
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

  Future<AccountUpgradeStatusModel> accountUpgradeGetStatus() async {
    final res = await _client.get(ApiEndpoints.accountUpgradeGetStatus);
    return AccountUpgradeStatusModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AccountUpgradeDocumentModel> accountUpgradeGetDetails(
      {required String accountUpgradeDocId}) async {
    final res = await _client.get(
      ApiEndpoints.accountUpgradeGetDetails,
      queryParams: {'account_upgrade_doc_id': accountUpgradeDocId},
    );
    return AccountUpgradeDocumentModel.fromJson(
      (res.data as Map<String, dynamic>)['document'] as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>?> getStatus({required String lenderId}) async {
    final res = await _client.get(
      ApiEndpoints.accountUpgradeGetStatus,
      queryParams: {'lender_id': lenderId},
    );
    return res.data as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>?> getDetails({
    String? accountUpgradeDocId,
    String? lenderId,
  }) async {
    final res = await _client.get(
      ApiEndpoints.accountUpgradeGetDetails,
      queryParams: {
        if (accountUpgradeDocId != null)
          'account_upgrade_doc_id': accountUpgradeDocId,
        if (lenderId != null) 'lender_id': lenderId,
      },
    );
    return res.data as Map<String, dynamic>?;
  }

  Future<void> verifyAccountUpgrade({
    required String accountUpgradeDocId,
    required String action,
    String? rejectionNotes,
  }) async {
    await _client.patch(
      ApiEndpoints.accountUpgradeVerify,
      data: {
        'account_upgrade_doc_id': accountUpgradeDocId,
        'action': action,
        if (rejectionNotes != null) 'rejection_notes': rejectionNotes,
      },
    );
  }

  Future<void> verifyAllAccountUpgrade({
    required String lenderId,
    required String action,
    String? rejectionNotes,
  }) async {
    await _client.patch(
      ApiEndpoints.accountUpgradeVerify,
      data: {
        'lender_id': lenderId,
        'action': action,
        if (rejectionNotes != null) 'rejection_notes': rejectionNotes,
      },
    );
  }

  Future<void> verify({
    required String accountUpgradeDocId,
    required String action,
    String? rejectionNotes,
  }) =>
      verifyAccountUpgrade(
        accountUpgradeDocId: accountUpgradeDocId,
        action: action,
        rejectionNotes: rejectionNotes,
      );

  Future<void> submitAccountUpgrade(
    List<Map<String, dynamic>> documents, {
    Map<String, dynamic>? info,
  }) async {
    await _client.post(ApiEndpoints.accountUpgradeSubmit, data: {
      'documents': documents,
      if (info != null) ...info,
    });
  }
}
