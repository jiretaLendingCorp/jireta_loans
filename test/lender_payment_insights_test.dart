// test/lender_payment_insights_test.dart
// Coverage para sa bagong feature:
//   • CURRENT outstanding balance ng lender (nagmumula sa lenders list /
//     lender details ng Head Manager at Employee)
//   • Early-payer detection: LAHAT ng verified na installment payment ay
//     binayaran BAGO o sa exactong due date (base sa loan term na kinuha).
//
// Ang tunay na aggregation ay nasa `lender_payment_insights` RPC
// (supabase/migrations/00161_lender_payment_insights.sql); dito natin
// hinihigpitan ang client-side parsing, ang UI-facing helpers, at ang
// wiring ng Edge Functions.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/user_model.dart';

/// Sinasalamin ang SQL rule: early payer = may verified payments AT walang late.
/// `payments` = listahan ng (paidOn, dueDate) — parehong Manila calendar dates.
bool isEarlyPayer(List<({DateTime paidOn, DateTime dueDate})> payments) {
  if (payments.isEmpty) return false;
  return payments.every(
    (p) => !p.paidOn.isAfter(p.dueDate),
  );
}

/// Read a repo file and normalize line endings (Windows checkouts use CRLF).
String readNormalized(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

Map<String, dynamic> lenderJson({
  double outstanding = 0,
  int activeLoans = 0,
  int settledLoans = 0,
  int verified = 0,
  int onTime = 0,
  int late = 0,
  int maxDaysEarly = 0,
  bool early = false,
}) =>
    {
      'id': 'lender-1',
      'role': 'lender',
      'first_name': 'Juan',
      'last_name': 'Dela Cruz',
      'account_status': 'active',
      'force_password_change': false,
      'created_at': '2026-01-05T00:00:00.000Z',
      'outstanding_balance': outstanding,
      'active_loans_count': activeLoans,
      'settled_loans_count': settledLoans,
      'verified_payment_count': verified,
      'on_time_payment_count': onTime,
      'late_payment_count': late,
      'max_days_early': maxDaysEarly,
      'is_early_payer': early,
    };

void main() {
  group('Lender insights — model parsing', () {
    test('outstanding balance + counts mula sa payload', () {
      final u = UserModel.fromJson(lenderJson(
        outstanding: 12500.50,
        activeLoans: 2,
        settledLoans: 1,
        verified: 6,
        onTime: 6,
        maxDaysEarly: 9,
        early: true,
      ));

      expect(u.outstandingBalance, 12500.50);
      expect(u.activeLoansCount, 2);
      expect(u.settledLoansCount, 1);
      expect(u.verifiedPaymentCount, 6);
      expect(u.onTimePaymentCount, 6);
      expect(u.maxDaysEarly, 9);
      expect(u.hasOutstanding, isTrue);
      expect(u.isEarlyPayer, isTrue);
      expect(u.hasPaymentHistory, isTrue);
    });

    test('walang insights field (legacy payload) — hindi mag-crash, 0 ang default', () {
      final u = UserModel.fromJson({
        'id': 'legacy',
        'role': 'lender',
        'first_name': 'Old',
        'last_name': 'Lender',
        'account_status': 'active',
        'created_at': '2026-01-05T00:00:00.000Z',
      });

      expect(u.outstandingBalance, 0);
      expect(u.activeLoansCount, 0);
      expect(u.settledLoansCount, 0);
      expect(u.verifiedPaymentCount, 0);
      expect(u.maxDaysEarly, 0);
      expect(u.isEarlyPayer, isFalse);
      expect(u.hasOutstanding, isFalse);
      expect(u.hasPaymentHistory, isFalse);
      expect(u.paymentBehaviorLabel, 'No payments yet');
    });

    test('fully paid lender — 0 outstanding pero may early-payer badge pa rin', () {
      final u = UserModel.fromJson(lenderJson(
        outstanding: 0,
        settledLoans: 2,
        verified: 12,
        onTime: 12,
        maxDaysEarly: 3,
        early: true,
      ));

      expect(u.hasOutstanding, isFalse);
      expect(u.isEarlyPayer, isTrue);
      expect(u.paymentBehaviorLabel, contains('Early payer'));
      expect(u.paymentBehaviorLabel, contains('up to 3 day(s) ahead'));
    });

    test('nagbayad ng late nang isang beses — HINDI early payer', () {
      final u = UserModel.fromJson(lenderJson(
        outstanding: 4000,
        activeLoans: 1,
        verified: 5,
        onTime: 4,
        late: 1,
        early: false,
      ));

      expect(u.isEarlyPayer, isFalse);
      expect(u.paymentBehaviorLabel, '1 of 5 payment(s) paid late');
    });

    test('on-time lahat pero walang nauna (0 days early) — early payer pa rin', () {
      final u = UserModel.fromJson(lenderJson(
        verified: 3,
        onTime: 3,
        maxDaysEarly: 0,
        early: true,
      ));

      expect(u.isEarlyPayer, isTrue);
      expect(u.paymentBehaviorLabel, 'Early payer — all 3 payment(s) on time');
    });

    test('copyWith preserves ang insights (hindi dapat ma-reset)', () {
      final u = UserModel.fromJson(lenderJson(
        outstanding: 750,
        activeLoans: 1,
        verified: 2,
        onTime: 2,
        maxDaysEarly: 5,
        early: true,
      ));
      final renamed = u.copyWith(firstName: 'Pedro');

      expect(renamed.firstName, 'Pedro');
      expect(renamed.outstandingBalance, 750);
      expect(renamed.isEarlyPayer, isTrue);
      expect(renamed.maxDaysEarly, 5);
    });
  });

  group('Early-payer rule (mirror ng SQL aggregation)', () {
    final due = DateTime(2026, 3, 10);

    test('lahat bago o sa exactong due date → early payer', () {
      expect(
        isEarlyPayer([
          (paidOn: DateTime(2026, 3, 8), dueDate: due),
          (paidOn: due, dueDate: due), // same-day counts as on time
        ]),
        isTrue,
      );
    });

    test('kahit isang araw na late → hindi early payer', () {
      expect(
        isEarlyPayer([
          (paidOn: DateTime(2026, 3, 8), dueDate: due),
          (paidOn: DateTime(2026, 3, 11), dueDate: due),
        ]),
        isFalse,
      );
    });

    test('walang verified payment → hindi early payer', () {
      expect(isEarlyPayer(const []), isFalse);
    });

    test('mas maagang bayad sa susunod na installment (advance) → early payer', () {
      // Isang bayad na inilapat sa ika-3 installment pero 20 araw bago ang due.
      expect(
        isEarlyPayer([
          (paidOn: DateTime(2026, 2, 18), dueDate: DateTime(2026, 4, 10)),
        ]),
        isTrue,
      );
    });
  });

  group('Backend wiring', () {
    test('migration 00161 ay may lender_payment_insights na may tamang columns', () async {
      final file = File('supabase/migrations/00161_lender_payment_insights.sql');
      expect(await file.exists(), isTrue);
      final sql = readNormalized(file.path);

      expect(sql, contains('CREATE OR REPLACE FUNCTION public.lender_payment_insights'));
      for (final col in [
        'outstanding_balance',
        'active_loans_count',
        'settled_loans_count',
        'verified_payment_count',
        'on_time_payment_count',
        'late_payment_count',
        'max_days_early',
        'is_early_payer',
      ]) {
        expect(sql, contains(col), reason: 'missing column $col');
      }
      // Manila calendar date ang basehan ng on-time check.
      expect(sql, contains("AT TIME ZONE 'Asia/Manila'"));
      // Hindi dapat ma-expose sa authenticated (lender) — service_role lang.
      expect(sql, contains('TO service_role'));
      expect(sql, isNot(contains('TO authenticated')));
    });

    test('users-admin get-list ay nagme-merge ng insights para sa lender rows', () async {
      final file = File('supabase/functions/users-admin/index.ts');
      expect(await file.exists(), isTrue);
      final ts = readNormalized(file.path);

      expect(ts, contains("rpc(\n      'lender_payment_insights'"));
      expect(ts, contains('p_lender_ids: lenderIds'));
      expect(ts, contains('m.outstanding_balance ='));
      expect(ts, contains('m.is_early_payer ='));
    });

    test('users-manage get-profile ay nagdadagdag ng insights sa lender profile', () async {
      final file = File('supabase/functions/users-manage/index.ts');
      expect(await file.exists(), isTrue);
      final ts = readNormalized(file.path);

      expect(ts, contains("'lender_payment_insights'"));
      expect(ts, contains('p_lender_ids: [canonicalId]'));
      expect(ts, contains("outstanding_balance: Number(lenderInsights?.outstanding_balance"));
      expect(ts, contains("is_early_payer: Boolean(lenderInsights?.is_early_payer"));
      // Lender lang ang kino-compute.
      expect(ts, contains("targetRole === 'lender'"));
    });

    test('Loan Records (HM + Employee) ay may Outstanding Balance column', () async {
      final hm = readNormalized(
          'lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart');
      final emp = readNormalized(
          'lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart');

      for (final src in [hm, emp]) {
        // Maikling header — ang "Outstanding Balance" ay napuputol sa column
        // (maxLines: 1 + ellipsis) kaya "Outstanding" ang label.
        expect(src, contains("ResponsiveCol('Outstanding'"));
        expect(src, isNot(contains("ResponsiveCol('Outstanding Balance'")));
        expect(src, contains('loan.outstandingBalance'));
        // Para LANG sa CURRENT ACTIVE LOAN (active/overdue) ang value.
        expect(src,
            contains("loan.status == 'active' || loan.status == 'overdue'"));
        expect(src, contains('isCurrentActiveLoan'));
        // Walang current active loan → "N/A", hindi blangko/dash.
        expect(src, contains(": 'N/A',"));
      }
      // Ang loan records screen ng HM/Employee ay pinamagatang "Loan Records".
      expect(hm, contains("title: 'Loan Records'"));
      expect(emp, contains("title: 'Loan Records'"));
    });

    test('Lenders (People) list ay HINDI na nagpapakita ng outstanding balance', () async {
      final hm = readNormalized(
          'lib/presentation/features/head_manager/lenders/screens/hm_lender_list_screen.dart');
      final emp = readNormalized(
          'lib/presentation/features/employee/lenders/screens/emp_lender_list_screen.dart');

      for (final src in [hm, emp]) {
        expect(src, isNot(contains("ResponsiveCol('Outstanding Balance'")));
        expect(src, isNot(contains('outstandingBalance')));
        // Early-payer badge ay nasa Collections → Early Payers tab na — hindi na
        // sa People/Lenders list.
        expect(src, isNot(contains('EarlyPayerBadge')));
        expect(src, isNot(contains('user.isEarlyPayer')));
      }
    });

    test(
        'Collections ay may Early Payers tab (HM + Employee) na naglilista ng mga early payer',
        () async {
      final hm = readNormalized(
          'lib/presentation/features/head_manager/collections/screens/hm_collection_list_screen.dart');
      final emp = readNormalized(
          'lib/presentation/features/employee/collections/screens/emp_collection_list_screen.dart');

      for (final src in [hm, emp]) {
        // Pill tab sa tabi ng Payments.
        expect(src, contains("FilterTabDef('early_payers', 'Early Payers'"));
        // Listahan galing sa lender insights (isEarlyPayer) at badge.
        expect(src, contains('isEarlyPayer'));
        expect(src, contains('EarlyPayerBadge'));
        expect(src, contains('_buildEarlyPayers'));
      }
    });
  });
}
