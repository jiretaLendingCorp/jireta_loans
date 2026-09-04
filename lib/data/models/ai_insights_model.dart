// lib/data/models/ai_insights_model.dart
//
// Parsed responses from the ai-dashboard-insights Edge Function. The AI only
// ever receives aggregated statistics and returns text — it never touches
// authoritative financial values (PostgreSQL remains the source of truth).

class AiInsightsModel {
  final String summary;
  final List<String> trends;
  final List<String> attention;
  final List<String> recommendations;
  final DateTime generatedAt; // actual generation timestamp from the backend
  final String? month; // YYYY-MM analyzed (null = lifetime)
  final String period;
  final String disclaimer;

  const AiInsightsModel({
    required this.summary,
    required this.trends,
    required this.attention,
    required this.recommendations,
    required this.generatedAt,
    this.month,
    this.period = 'lifetime',
    this.disclaimer = '',
  });

  factory AiInsightsModel.fromJson(Map<String, dynamic> json) {
    final rawInsights = json['insights'];
    final insights = rawInsights is Map
        ? Map<String, dynamic>.from(rawInsights)
        : <String, dynamic>{};
    String safeString(dynamic v) => v?.toString() ?? '';
    List<String> safeList(dynamic v) =>
        (v as List?)?.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList() ??
            const [];
    return AiInsightsModel(
      summary: safeString(insights['summary']),
      trends: safeList(insights['trends']),
      attention: safeList(insights['attention']),
      recommendations: safeList(insights['recommendations']),
      generatedAt:
          DateTime.tryParse(safeString(json['generated_at']))?.toLocal() ??
              DateTime.now(),
      month: json['month']?.toString(),
      period: json['period']?.toString() ?? 'lifetime',
      disclaimer: safeString(json['disclaimer']),
    );
  }
}

class AiAnswerModel {
  final String answer;
  final String intent;
  final DateTime generatedAt;

  const AiAnswerModel({
    required this.answer,
    required this.intent,
    required this.generatedAt,
  });

  factory AiAnswerModel.fromJson(Map<String, dynamic> json) {
    return AiAnswerModel(
      answer: json['answer']?.toString() ?? '',
      intent: json['intent']?.toString() ?? 'other',
      generatedAt:
          DateTime.tryParse(json['generated_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}