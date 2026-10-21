// test/features/head_manager/rider_monitoring/rider_monitoring_model_test.dart
//
// Ang Rider Collection Monitoring ay read-only at ang lahat ng numero ay galing
// sa `rider_collection_monitoring` RPC. Dito sinusuri na:
//   • tama ang parsing ng summary at per-rider rows (walang client-side math),
//   • hindi nag-crash kapag kulang/walang laman (empty states),
//   • Manila ang timestamp handling (pareho ng ibang screens).
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/models/rider_collection_monitoring_model.dart';

void main() {
  group('RiderMonitoringPage', () {
    test('parses summary at rows mula sa server payload', () {
      final page = RiderMonitoringPage.fromJson({
        'data': [
          {
            'rider_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'rider_name': 'Juan Dela Cruz',
            'phone_number': '09171234567',
            'plate_number': 'ABC-123',
            'vehicle_type': 'Motorcycle',
            'is_available': true,
            'assigned_accounts': 4,
            'assigned_installments': 6,
            'expected_collection': 12000.0,
            'confirmed_collection': 7500.5,
            'remaining_due': 4499.5,
            'overdue_accounts': 2,
            'overdue_installments': 3,
            'open_assignments': 1,
            'last_activity_at': '2026-10-20T01:00:00.000Z',
            'collection_performance': 62.5,
          },
        ],
        'summary': {
          'active_riders': 1,
          'assigned_accounts': 4,
          'assigned_installments': 6,
          'expected_collection': 12000.0,
          'confirmed_collection': 7500.5,
          'remaining_due': 4499.5,
          'overdue_accounts': 2,
          'overdue_installments': 3,
          'open_assignments': 1,
          'confirmed_payment_count': 5,
          'collection_performance': 62.5,
        },
        'total': 1,
        'page': 1,
        'totalPages': 1,
      });

      expect(page.total, 1);
      expect(page.rows, hasLength(1));
      final row = page.rows.single;
      expect(row.riderName, 'Juan Dela Cruz');
      expect(row.assignedAccounts, 4);
      expect(row.expectedCollection, 12000.0);
      expect(row.confirmedCollection, 7500.5);
      expect(row.remainingDue, 4499.5);
      expect(row.overdueAccounts, 2);
      expect(row.isAvailable, isTrue);
      // parseManila: UTC instant → Manila wall time (+8h).
      expect(row.lastActivityAt!.hour, 9);

      expect(page.summary.activeRiders, 1);
      expect(page.summary.confirmedPayments, 5);
      expect(page.summary.collectionPerformance, 62.5);
    });

    test('empty payload → zero summary at walang rows (empty state)', () {
      final page = RiderMonitoringPage.fromJson({});
      expect(page.rows, isEmpty);
      expect(page.summary.activeRiders, 0);
      expect(page.summary.expectedCollection, 0);
      expect(page.summary.collectionPerformance, isNull);
    });
  });

  group('RiderMonitoringDetail', () {
    test('parses accounts, payments at history', () {
      final detail = RiderMonitoringDetail.fromJson({
        'data': {
          'rider': {'rider_id': 'r-1', 'rider_name': 'Maria Santos'},
          'summary': {
            'expected_collection': 3000,
            'confirmed_collection': 1000,
            'remaining_due': 2000,
            'overdue_accounts': 1,
          },
          'monitoring': {
            'rider_id': 'r-1',
            'rider_name': 'Maria Santos',
            'assigned_accounts': 1,
          },
          'accounts': [
            {
              'loan_number': 'JR-1001',
              'lender_name': 'Pedro Reyes',
              'outstanding_balance': 2000,
              'assigned_installments': 1,
              'schedules': [
                {
                  'installment_number': 1,
                  'due_date': '2026-10-01',
                  'amount_due': 3000,
                  'amount_paid': 1000,
                  'remaining_due': 2000,
                  'status': 'overdue',
                  'confirmed_collection': 1000,
                },
              ],
            },
          ],
          'payments': [
            {
              'id': 'p-1',
              'amount': 1000,
              'status': 'verified',
              'paid_at': '2026-10-05T02:00:00.000Z',
            },
          ],
          'history': [
            {
              'assignment_id': 'a-1',
              'status': 'completed',
              'amount_collected': 1000,
            },
          ],
        },
        'generated_at': '2026-10-20T01:00:00.000Z',
      });

      expect(detail.rider['rider_name'], 'Maria Santos');
      expect(detail.summary.remainingDue, 2000);
      expect(detail.monitoring?.riderName, 'Maria Santos');
      expect(detail.accounts.single['loan_number'], 'JR-1001');
      expect(detail.payments.single['amount'], 1000);
      expect(detail.history.single['status'], 'completed');
      expect(detail.generatedAt!.hour, 9);
    });

    test('walang data → safe na empty collections', () {
      final detail = RiderMonitoringDetail.fromJson({});
      expect(detail.rider, isEmpty);
      expect(detail.accounts, isEmpty);
      expect(detail.payments, isEmpty);
      expect(detail.history, isEmpty);
      expect(detail.monitoring, isNull);
    });
  });
}
