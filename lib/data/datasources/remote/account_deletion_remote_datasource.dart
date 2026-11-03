// lib/data/datasources/remote/account_deletion_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/account_deletion_request_model.dart';

/// Client para sa `account-delete` Edge Function.
///
/// * [requestDeletion] — PUBLIC form ng `/delete-account` page (Google Play
///   Delete Account URL). Walang session; ang server ang nag-rate-limit at
///   nagre-record ng request para sa manual identity verification.
/// * [deleteSelf] — naka-log-in na lender/rider; agad na dini-delete ang
///   account kapag walang active/overdue loan.
class AccountDeletionRemoteDataSource {
  final DioClient _client;
  AccountDeletionRemoteDataSource(this._client);

  Future<Map<String, dynamic>> requestDeletion({
    required String identifier,
    required String fullName,
    String? reason,
  }) async {
    final res = await _client.post(
      ApiEndpoints.accountDeleteRequest,
      data: {
        'identifier': identifier,
        'full_name': fullName,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> deleteSelf({
    required String confirmation,
    String? reason,
  }) async {
    final res = await _client.post(
      ApiEndpoints.accountDeleteSelf,
      data: {
        'confirmation': confirmation,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  /// Head Manager queue. [status] is `pending`, `processing`, `completed`,
  /// `rejected`, or `all`.
  Future<List<AccountDeletionRequestModel>> listRequests({
    String status = 'pending',
  }) async {
    // Ang Edge Function ay POST-only (405 sa GET) — pareho ito ng ibang
    // `fn=` actions, kaya POST din ang queue listing.
    final res = await _client.post(
      '${ApiEndpoints.accountDeleteListRequests}'
      '&status=${Uri.encodeQueryComponent(status)}',
    );
    final data = res.data;
    final raw = data is Map ? data['requests'] : null;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => AccountDeletionRequestModel.fromJson(
              row.cast<String, dynamic>(),
            ))
        .where((row) => row.id.isNotEmpty)
        .toList();
  }

  /// Approve (`action: 'approve'`) or reject (`action: 'reject'`) a public
  /// request. Approval runs the real deletion server-side.
  Future<Map<String, dynamic>> processRequest({
    required String requestId,
    required String action,
    String? notes,
  }) async {
    final res = await _client.post(
      ApiEndpoints.accountDeleteProcessRequest,
      data: {
        'request_id': requestId,
        'action': action,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return (res.data as Map).cast<String, dynamic>();
  }
}
