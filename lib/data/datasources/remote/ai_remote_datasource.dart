// lib/data/datasources/remote/ai_remote_datasource.dart
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../models/ai_insights_model.dart';

/// Talks to the ai-dashboard-insights Supabase Edge Function.
///
/// The Gemini API key and all business data access live server-side — Flutter
/// only sends the selected month / question and receives validated text.
class AiRemoteDataSource {
  final DioClient _client;
  AiRemoteDataSource(this._client);

  Future<AiInsightsModel> generateInsights({String? month}) async {
    final res = await _client.post(
      ApiEndpoints.aiGenerateInsights,
      data: {if (month != null && month.isNotEmpty) 'month': month},
    );
    return AiInsightsModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AiAnswerModel> ask({
    required String question,
    String? month,
  }) async {
    final res = await _client.post(
      ApiEndpoints.aiAsk,
      data: {
        'question': question,
        if (month != null && month.isNotEmpty) 'month': month,
      },
    );
    return AiAnswerModel.fromJson(res.data as Map<String, dynamic>);
  }
}