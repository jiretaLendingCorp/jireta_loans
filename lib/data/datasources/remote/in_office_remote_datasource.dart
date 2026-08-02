// lib/data/datasources/remote/in_office_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';

class InOfficeRemoteDataSource {
  final DioClient _client;
  InOfficeRemoteDataSource(this._client);

  Future<Map<String, dynamic>> createDraft() async {
    final res = await _client.post(ApiEndpoints.inOfficeCreateDraft, data: {});
    return res.data as Map<String, dynamic>;
  }

  Future<void> saveStep({
    required String applicationId,
    required int step,
    required Map<String, dynamic> data,
  }) async {
    await _client.patch(
      ApiEndpoints.inOfficeSaveStep,
      data: {'application_id': applicationId, 'step': step, 'data': data},
    );
  }

  Future<Map<String, dynamic>> submit({
    required String applicationId,
  }) async {
    final res = await _client.post(
      ApiEndpoints.inOfficeSubmit,
      data: {'application_id': applicationId},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getList({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.inOfficeGetList,
      queryParams: {
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getSchedulePreview({
    required double principal,
    required String frequency,
  }) async {
    final res = await _client.post(
      ApiEndpoints.loansGetSchedulePreview,
      data: {'principal': principal, 'frequency': frequency},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getApplicationList({
    String? status,
    int page = 1,
    int limit = 20,
  }) =>
      getList(status: status, page: page, limit: limit);

  Future<Map<String, dynamic>> submitApplication({
    required String applicationId,
  }) =>
      submit(applicationId: applicationId);
}
