// test/features/head_manager/rider_quotas/rider_quota_model_test.dart
//
// Ang quota numbers ay galing sa server (00187). Dito sinusuri ang parsing,
// ang 100% cap ng progress bar (habang buo pa rin ang actual amount), at ang
// client-side validation na dapat tumugma sa backend rules.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/models/rider_quota_model.dart';

void main() {
  group('RiderQuota parsing', () {
    test('monitoring row → exact amounts, dates at derived status', () {
      final q = RiderQuota.fromJson({
        'quota_id': '11111111-1111-1111-1111-111111111111',
        'rider_id': '22222222-2222-2222-2222-222222222222',
        'rider_name': 'Anthony Maramba',
        'phone_number': '09635267491',
        'period': 'daily',
        'target_amount': 10000,
        'confirmed_collection': 7500.5,
        'remaining_target': 2499.5,
        'completion_percentage': 75.01,
        'start_date': '2026-10-21',
        'end_date': '2026-10-21',
        'status': 'active',
        'is_active': true,
        'achieved': false,
        'payment_count': 3,
        'last_paid_at': '2026-10-21T02:30:00Z',
        'notes': 'Morning route',
      });

      expect(q.riderName, 'Anthony Maramba');
      expect(q.targetAmount, 10000);
      expect(q.confirmedCollection, 7500.5);
      expect(q.remainingTarget, 2499.5);
      expect(q.completionPercentage, 75.01);
      expect(q.startDate, DateTime(2026, 10, 21));
      expect(q.endDate, DateTime(2026, 10, 21));
      expect(q.status, RiderQuotaStatus.active);
      expect(q.isEditable, isTrue);
      expect(q.progress, closeTo(0.7501, 0.0001));
      // 02:30Z → 10:30 Manila
      expect(q.lastPaidAt?.hour, 10);
    });

    test('lumampas sa target: buo ang confirmed, 1.0 ang progress bar', () {
      final q = RiderQuota.fromJson({
        'quota_id': 'q',
        'rider_id': 'r',
        'target_amount': 1000,
        'confirmed_collection': 1250,
        'remaining_target': 0,
        'completion_percentage': 125,
        'status': 'active',
        'is_active': true,
        'achieved': true,
      });

      expect(q.confirmedCollection, 1250);
      expect(q.completionPercentage, 125);
      expect(q.progress, 1.0); // capped display
      expect(q.isOverTarget, isTrue);
      expect(q.achieved, isTrue);
    });

    test('tapos nang period ay hindi na editable', () {
      final q = RiderQuota.fromJson({
        'quota_id': 'q',
        'rider_id': 'r',
        'target_amount': 500,
        'status': 'expired',
        'is_active': true,
      });
      expect(q.isOpen, isFalse);
      expect(q.isEditable, isFalse);
    });
  });

  group('status labels', () {
    test('expired → "Missed", hindi "Expired"', () {
      // Tapos na ang period at hindi naabot ang target — performance result
      // ito, hindi system expiration.
      expect(RiderQuotaStatus.label('expired'), 'Missed');
      expect(RiderQuotaStatus.label('completed'), 'Completed');
    });
  });

  group('RiderQuotaPage / summary', () {
    test('parses data + summary + pagination', () {
      final page = RiderQuotaPage.fromJson({
        'data': [
          {
            'quota_id': 'q1',
            'rider_id': 'r1',
            'target_amount': 1000,
            'confirmed_collection': 400,
            'remaining_target': 600,
            'completion_percentage': 40,
            'status': 'active',
          }
        ],
        'summary': {
          'active_riders': 1,
          'assigned_quota': 1000,
          'confirmed_total': 400,
          'remaining_total': 600,
          'riders_met': 0,
          'open_quotas': 1,
          'total_quotas': 3,
          'expired_quotas': 2,
        },
        'total': 1,
        'page': 1,
        'totalPages': 1,
      });

      expect(page.rows.single.quotaId, 'q1');
      expect(page.summary.activeRiders, 1);
      expect(page.summary.assignedQuota, 1000);
      expect(page.summary.confirmedTotal, 400);
      expect(page.summary.remainingTotal, 600);
      expect(page.summary.ridersMet, 0);
      expect(page.summary.expiredQuotas, 2);
      expect(page.totalPages, 1);
    });

    test('empty payload → zero summary at walang rows', () {
      final page = RiderQuotaPage.fromJson({});
      expect(page.rows, isEmpty);
      expect(page.summary.assignedQuota, 0);
      expect(page.total, 0);
    });
  });

  group('RiderQuotaSelf', () {
    test('current, history at verified payments', () {
      final self = RiderQuotaSelf.fromJson({
        'current': {
          'quota_id': 'cur',
          'period': 'weekly',
          'target_amount': 5000,
          'confirmed_collection': 1200,
          'remaining_target': 3800,
          'completion_percentage': 24,
          'start_date': '2026-10-19',
          'end_date': '2026-10-25',
          'status': 'active',
        },
        'history': [
          {
            'quota_id': 'old',
            'period': 'daily',
            'target_amount': 1000,
            'confirmed_collection': 1000,
            'remaining_target': 0,
            'completion_percentage': 100,
            'status': 'completed',
            'achieved': true,
          }
        ],
        'payments': [
          {
            'payment_id': 'p1',
            'amount': 700,
            'paid_at': '2026-10-20T01:00:00Z',
            'payment_method': 'rider_collection',
            'loan_number': 'JL-0001',
            'installment_number': 2,
          }
        ],
      });

      expect(self.current?.quotaId, 'cur');
      expect(self.history.single.achieved, isTrue);
      expect(self.payments.single.amount, 700);
      expect(self.payments.single.loanNumber, 'JL-0001');
      expect(self.payments.single.installmentNumber, 2);
    });

    test('walang quota → null current at empty lists', () {
      final self = RiderQuotaSelf.fromJson({});
      expect(self.current, isNull);
      expect(self.history, isEmpty);
      expect(self.payments, isEmpty);
    });
  });

  group('validateRiderQuotaInput', () {
    test('daily = isang araw lang', () {
      final day = DateTime(2026, 10, 21);
      expect(
        validateRiderQuotaInput(
            period: 'daily',
            targetAmount: 1000,
            startDate: day,
            endDate: day),
        isNull,
      );
      expect(
        validateRiderQuotaInput(
            period: 'daily',
            targetAmount: 1000,
            startDate: day,
            endDate: day.add(const Duration(days: 1))),
        contains('1 day'),
      );
    });

    test('weekly = eksaktong 7 araw', () {
      final start = DateTime(2026, 10, 19);
      expect(
        validateRiderQuotaInput(
            period: 'weekly',
            targetAmount: 5000,
            startDate: start,
            endDate: start.add(const Duration(days: 6))),
        isNull,
      );
      expect(
        validateRiderQuotaInput(
            period: 'weekly',
            targetAmount: 5000,
            startDate: start,
            endDate: start.add(const Duration(days: 5))),
        isNotNull,
      );
    });

    test('monthly = 28–31 araw', () {
      expect(
        validateRiderQuotaInput(
            period: 'monthly',
            targetAmount: 50000,
            startDate: DateTime(2026, 10, 1),
            endDate: DateTime(2026, 10, 31)),
        isNull,
      );
      expect(
        validateRiderQuotaInput(
            period: 'monthly',
            targetAmount: 50000,
            startDate: DateTime(2026, 10, 1),
            endDate: DateTime(2026, 10, 20)),
        isNotNull,
      );
    });

    test('zero/negative target at baliktad na dates ay tinatanggihan', () {
      final day = DateTime(2026, 10, 21);
      expect(
        validateRiderQuotaInput(
            period: 'daily', targetAmount: 0, startDate: day, endDate: day),
        contains('greater than zero'),
      );
      expect(
        validateRiderQuotaInput(
            period: 'weekly',
            targetAmount: 1000,
            startDate: day,
            endDate: day.subtract(const Duration(days: 1))),
        contains('End date'),
      );
    });
  });

  group('riderQuotaDefaultRange', () {
    test('daily ay ngayon lang', () {
      final r = riderQuotaDefaultRange('daily', DateTime(2026, 10, 21, 15));
      expect(r.start, DateTime(2026, 10, 21));
      expect(r.end, DateTime(2026, 10, 21));
    });

    test('weekly ay Lunes–Linggo', () {
      final r = riderQuotaDefaultRange('weekly', DateTime(2026, 10, 21));
      expect(r.start, DateTime(2026, 10, 19)); // Monday
      expect(r.end, DateTime(2026, 10, 25)); // Sunday
    });

    test('monthly ay buong buwan', () {
      final r = riderQuotaDefaultRange('monthly', DateTime(2026, 2, 10));
      expect(r.start, DateTime(2026, 2, 1));
      expect(r.end, DateTime(2026, 2, 28));
    });
  });
}
