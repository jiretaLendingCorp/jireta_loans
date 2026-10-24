// test/schedule_status_test.dart
//
// STATUS SA PAYMENT SCHEDULE: "Overdue paid"
//
// Kapag binayaran ang installment pagkalampas ng due date, "Overdue paid" ang
// dapat na label — hindi lang "Paid" — para makita ng HM/Employee na may
// dating overdue na nabayaran ang lender.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/utils/schedule_status.dart';

Map<String, dynamic> _s({
  required String status,
  String? dueDate,
  String? paidAt,
  double amountDue = 200,
  double amountPaid = 0,
}) =>
    {
      'status': status,
      'due_date': dueDate,
      'paid_at': paidAt,
      'amount_due': amountDue,
      'amount_paid': amountPaid,
    };

void main() {
  group('isLatePaidSchedule', () {
    test('bayad pagkalampas ng due date → late paid', () {
      expect(
          isLatePaidSchedule(_s(
            status: 'paid',
            dueDate: '2026-09-26',
            paidAt: '2026-09-27T13:32:00Z',
            amountPaid: 200,
          )),
          isTrue);
    });

    test('bayad sa mismong due date → on time', () {
      expect(
          isLatePaidSchedule(_s(
            status: 'paid',
            dueDate: '2026-09-26',
            paidAt: '2026-09-26T01:00:00Z',
            amountPaid: 200,
          )),
          isFalse);
    });

    test('Manila date ang gamit: 7 AM Manila sa due date ay on time', () {
      // 2026-09-25 23:00 UTC = 2026-09-26 07:00 Manila — parehong araw.
      expect(
          isLatePaidSchedule(_s(
            status: 'paid',
            dueDate: '2026-09-26',
            paidAt: '2026-09-25T23:00:00Z',
            amountPaid: 200,
          )),
          isFalse);
    });

    test('hindi pa bayad → hindi late paid', () {
      expect(
          isLatePaidSchedule(_s(status: 'overdue', dueDate: '2026-09-26')),
          isFalse);
    });

    test('bayad na pero walang paid_at → hindi late paid', () {
      expect(
          isLatePaidSchedule(_s(
            status: 'paid',
            dueDate: '2026-09-26',
            amountPaid: 200,
          )),
          isFalse);
    });
  });

  group('scheduleStatusLabel', () {
    test('late paid → "Overdue paid" na may petsa at oras ng bayad', () {
      expect(
          scheduleStatusLabel(_s(
            status: 'paid',
            dueDate: '2026-09-26',
            paidAt: '2026-09-27T13:32:00Z',
            amountPaid: 200,
          )),
          'Overdue paid · Sep 27, 2026 9:32 PM');
    });

    test('latePaidDateLabel: petsa at oras ng bayad sa Manila, null kapag on-time',
        () {
      expect(
          latePaidDateLabel(_s(
            status: 'paid',
            dueDate: '2026-09-26',
            paidAt: '2026-09-27T13:32:00Z',
            amountPaid: 200,
          )),
          'Sep 27, 2026 9:32 PM');
      expect(
          latePaidDateLabel(_s(
            status: 'paid',
            dueDate: '2026-09-26',
            paidAt: '2026-09-26T01:00:00Z',
            amountPaid: 200,
          )),
          isNull);
    });

    test('on-time paid → "Paid" pa rin', () {
      expect(
          scheduleStatusLabel(_s(
            status: 'paid',
            dueDate: '2026-09-26',
            paidAt: '2026-09-26T01:00:00Z',
            amountPaid: 200,
          )),
          'Paid');
    });

    test('iba pang status ay capitalized na', () {
      expect(scheduleStatusLabel(_s(status: 'overdue')), 'Overdue');
      expect(scheduleStatusLabel(_s(status: 'partial')), 'Partial');
      expect(scheduleStatusLabel(_s(status: 'pending')), 'Pending');
    });

    test('blangko ang status → fallback', () {
      expect(scheduleStatusLabel(_s(status: '')), '-');
    });
  });

  group('Lahat ng Payment Schedule table ay gumagamit ng shared helper', () {
    test('HM at Employee schedule tables → scheduleStatusLabel', () {
      for (final path in const [
        'lib/presentation/features/head_manager/loans/screens/hm_loan_application_details_screen.dart',
        'lib/presentation/features/head_manager/loans/screens/hm_loan_details_screen.dart',
        'lib/presentation/features/head_manager/loans/widgets/loan_application_details_modal.dart',
        'lib/presentation/features/head_manager/loans/widgets/loan_details_modal.dart',
        'lib/presentation/features/head_manager/loans/widgets/loan_details_side_panel.dart',
        'lib/presentation/features/employee/loans/screens/emp_loan_application_details_screen.dart',
        'lib/presentation/features/employee/loans/screens/emp_loan_details_screen.dart',
        'lib/presentation/features/employee/loans/widgets/emp_loan_details_modal.dart',
      ]) {
        final src = File(path)
            .readAsStringSync()
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n');
        expect(src, contains('schedule_status.dart'),
            reason: '$path: dapat gamitin ang shared schedule status helper');
        expect(
            src.contains('scheduleStatusLabel(') ||
                src.contains('isLatePaidSchedule('),
            isTrue,
            reason: '$path: dapat may "Overdue paid" na label');
      }
    });
  });

  group('Overdue paid sa Collections → Payments list (HM + Employee)', () {
    test('parehong payments table ay nagbabasa ng `paid_overdue`', () {
      for (final path in const [
        'lib/presentation/features/head_manager/collections/screens/hm_collection_list_screen.dart',
        'lib/presentation/features/employee/collections/screens/emp_collection_list_screen.dart',
      ]) {
        final src = File(path)
            .readAsStringSync()
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n');
        expect(src, contains("p['paid_overdue'] == true"),
            reason: '$path: dapat may "Overdue paid" sa status cell');
        expect(src, contains("'Overdue paid · "),
            reason: '$path: dapat may petsa at oras ang "Overdue paid" tag');
      }
    });
  });
}
