// test/ai_insights_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/ai_insights_model.dart';

void main() {
  group('AiInsightsModel.fromJson', () {
    test('parses a full valid payload', () {
      final model = AiInsightsModel.fromJson({
        'insights': {
          'summary': 'Portfolio is stable.',
          'trends': ['Applications steady'],
          'attention': ['No overdue loans'],
          'recommendations': ['Keep monitoring'],
        },
        'generated_at': '2026-09-04T02:30:00.000Z',
        'month': '2026-09',
        'period': 'monthly',
        'disclaimer': 'Aggregated only.',
      });

      expect(model.summary, 'Portfolio is stable.');
      expect(model.trends, ['Applications steady']);
      expect(model.attention, ['No overdue loans']);
      expect(model.recommendations, ['Keep monitoring']);
      expect(model.month, '2026-09');
      expect(model.period, 'monthly');
      expect(model.disclaimer, 'Aggregated only.');
      // generated_at is UTC, converted to local — just assert it parses.
      expect(model.generatedAt, isA<DateTime>());
    });

    test('tolerates missing fields and non-list lists', () {
      final model = AiInsightsModel.fromJson({
        'insights': {},
        'generated_at': null,
      });

      expect(model.summary, '');
      expect(model.trends, isEmpty);
      expect(model.attention, isEmpty);
      expect(model.recommendations, isEmpty);
      expect(model.month, isNull);
    });

    test('strips empty strings from lists', () {
      final model = AiInsightsModel.fromJson({
        'insights': {
          'trends': ['real', '', null, 'second'],
        },
      });
      expect(model.trends, ['real', 'second']);
    });
  });

  group('AiAnswerModel.fromJson', () {
    test('parses answer payload', () {
      final answer = AiAnswerModel.fromJson({
        'answer': 'There are 0 overdue loans.',
        'intent': 'overdue_summary',
        'generated_at': '2026-09-04T02:30:00.000Z',
      });
      expect(answer.answer, 'There are 0 overdue loans.');
      expect(answer.intent, 'overdue_summary');
    });

    test('tolerates missing fields', () {
      final answer = AiAnswerModel.fromJson({});
      expect(answer.answer, '');
      expect(answer.intent, 'other');
    });
  });
}