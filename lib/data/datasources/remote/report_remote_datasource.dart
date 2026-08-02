// lib/data/datasources/remote/report_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/report_model.dart';

class ReportRemoteDataSource {
  final DioClient _client;
  ReportRemoteDataSource(this._client);

  Future<List<ReportTemplateModel>> getReportTemplates() async {
    final res = await _client.get(ApiEndpoints.reportsGetList);
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map((e) => ReportTemplateModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GeneratedReportModel>> getReportHistory({
    String? type,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.reportsGetHistory,
      queryParams: {
        if (type != null) 'type': type,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map((e) => GeneratedReportModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> generateReport({
    required String templateKey,
    required Map<String, dynamic> parameters,
    required String format,
  }) async {
    final res = await _client.post(
      ApiEndpoints.reportsGenerate,
      data: {
        'template_key': templateKey,
        'parameters': parameters,
        'format': format,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<List<ReportTemplateModel>> getList() => getReportTemplates();

  Future<List<GeneratedReportModel>> getHistory({
    int page = 1,
    int limit = 20,
  }) =>
      getReportHistory(page: page, limit: limit);

  Future<bool> generate({
    required String templateKey,
    Map<String, dynamic> parameters = const {},
  }) async {
    await generateReport(
      templateKey: templateKey,
      parameters: parameters,
      format: 'pdf',
    );
    return true;
  }

  Future<List<Map<String, dynamic>>> getReportList({
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.reportsGetList,
      queryParams: {'page': page, 'limit': limit},
    );
    final list = (res.data['data'] as List?) ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getRawHistory({
    String? type,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.reportsGetHistory,
      queryParams: {
        if (type != null) 'type': type,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list.cast<Map<String, dynamic>>();
  }
}
