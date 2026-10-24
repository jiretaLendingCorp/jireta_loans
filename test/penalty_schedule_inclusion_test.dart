// test/penalty_schedule_inclusion_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// BUSINESS RULE: kapag nag-overdue ang lender at na-apply ang 20% penalty,
// DAPAT KASAMA ito sa BABAYARAN niya — hindi lang sa `outstanding_balance`.
//
// Dati: ang penalty ay nasa `penalty_logs` at sa DERIVED na outstanding
// (total_payable + penalties - verified payments), pero ang `loan_schedules`
// ay total_payable pa rin ang kabuuan. Kaya kapag binayaran ng lender ang
// lahat ng installment (lalo na via GCash, kung saan EKSAKTONG
// `loan_schedules.amount_due` ang siningil), may natitira pang 20% na hindi
// mababayaran at hindi nag-cocompleted ang loan.
//
// Ngayon (00190): idinadagdag ang penalty sa HULING UNPAID installment, kaya
// ang kabuuan ng natitirang installment = total_payable + penalties.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

double _round2(double n) => (n * 100).round() / 100;

/// Mirror ng `sync_loan_schedule_penalties()` (00190): idinadagdag sa huling
/// unpaid installment ang gap ng (total_payable + penalties) laban sa
/// kabuuan ng `amount_due`. Idempotent — gap = 0 pagkatapos ng unang tawag.
List<double> foldPenalty({
  required double totalPayable,
  required List<double> dues,
  required double penalties,
  List<double>? paid,
  double threshold = 0.004,
}) {
  final result = List<double>.from(dues);
  if (penalties <= 0) return result;
  final scheduled = _round2(result.fold<double>(0, (s, d) => s + d));
  final gap = _round2(totalPayable + penalties - scheduled);
  if (gap <= threshold) return result;

  final paidByRow = paid ?? List<double>.filled(result.length, 0);
  var target = -1;
  for (var i = 0; i < result.length; i++) {
    final remaining = _round2(result[i] - paidByRow[i]);
    if (remaining > threshold) target = i;
  }
  // Fallback: bayad na lahat pero may penalty pa (lumang data) — ang huling
  // installment pa rin ang gagalawin, kaya magiging `partial` ito.
  if (target < 0) target = result.length - 1;
  result[target] = _round2(result[target] + gap);
  return result;
}

/// Outstanding balance = total_payable + penalties - verified payments.
double outstanding({
  required double totalPayable,
  required double penalties,
  required double payments,
}) =>
    _round2(totalPayable + penalties - payments);

void main() {
  group('Penalty ay kasama sa babayaran (installment amounts)', () {
    test('20% penalty ay idinadagdag sa huling unpaid installment', () {
      // ₱10,000 principal @ 20% → total payable ₱12,000, 6 x ₱2,000.
      // Walang bayad → outstanding ₱12,000 → penalty 20% = ₱2,400.
      final dues = foldPenalty(
        totalPayable: 12000,
        dues: List<double>.filled(6, 2000),
        penalties: 2400,
      );

      expect(dues.sublist(0, 5), everyElement(2000));
      expect(dues.last, 4400, reason: 'huling installment ang may penalty');
      expect(
        _round2(dues.fold<double>(0, (s, d) => s + d)),
        14400,
        reason: 'total ng schedule = total payable + penalty',
      );
    });

    test('idempotent — hindi nadodoble kapag tumakbo muli', () {
      final once = foldPenalty(
        totalPayable: 12000,
        dues: List<double>.filled(6, 2000),
        penalties: 2400,
      );
      final twice = foldPenalty(
        totalPayable: 12000,
        dues: once,
        penalties: 2400,
      );
      expect(twice, once);
    });

    test('partially paid na huling installment → penalty pa rin ang idadagdag',
        () {
      final dues = foldPenalty(
        totalPayable: 12000,
        dues: List<double>.filled(6, 2000),
        penalties: 2400,
        paid: [2000, 2000, 2000, 2000, 2000, 500],
      );
      expect(dues.last, 4400);
      expect(dues.sublist(0, 5), everyElement(2000));
    });

    test('bayad na ang huling installment → penalty sa huling UNPAID pa rin',
        () {
      // Posible kapag advance payment (pinindot na installment) — ang
      // pinakamataas na row ay bayad na pero may unpaid pa sa ilalim.
      final dues = foldPenalty(
        totalPayable: 12000,
        dues: List<double>.filled(6, 2000),
        penalties: 2400,
        paid: [2000, 2000, 2000, 2000, 0, 2000],
      );
      expect(dues, [2000, 2000, 2000, 2000, 4400, 2000]);
    });

    test('walang penalty → walang binabago', () {
      final dues = foldPenalty(
        totalPayable: 12000,
        dues: List<double>.filled(6, 2000),
        penalties: 0,
      );
      expect(dues, List<double>.filled(6, 2000));
    });

    test('bayad na lahat pero may penalty pa → huling installment pa rin', () {
      // Lumang data: nabayaran na ang total payable (₱12,000) bago/noon
      // na-apply ang 20% penalty. Walang unpaid row, kaya ang huling
      // installment ang ginagawang `partial` — may mababayaran pa rin.
      final dues = foldPenalty(
        totalPayable: 12000,
        dues: List<double>.filled(6, 2000),
        penalties: 2400,
        paid: List<double>.filled(6, 2000),
      );
      expect(dues.sublist(0, 5), everyElement(2000));
      expect(dues.last, 4400, reason: '₱2,000 bayad + ₱2,400 penalty');
    });
  });

  group('Pagkabayad ng lahat ng installment → 0 ang outstanding', () {
    test('kasama ang penalty sa huling bayad kaya nag-cocompleted', () {
      const totalPayable = 12000.0;
      const penalties = 2400.0;
      final dues = foldPenalty(
        totalPayable: totalPayable,
        dues: List<double>.filled(6, 2000),
        penalties: penalties,
      );

      // Bayaran ang lahat ng installment base sa aktwal na amount_due.
      final payments = dues.fold<double>(0, (s, d) => s + d);
      expect(payments, 14400);
      expect(
        outstanding(
          totalPayable: totalPayable,
          penalties: penalties,
          payments: payments,
        ),
        0,
        reason: 'dapat zero ang balance pagkatapos bayaran ang schedule',
      );
    });

    test('kung hindi isasama ang penalty, may natitirang ₱2,400', () {
      expect(
        outstanding(totalPayable: 12000, penalties: 2400, payments: 12000),
        2400,
        reason: 'ito ang dating bug — hindi nag-cocompleted ang loan',
      );
    });
  });

  group('Source guards', () {
    test('00190: may sync function at idinadagdag sa huling unpaid installment',
        () {
      final src = _squash(
          _read('supabase/migrations/00190_penalty_into_installments.sql'));
      expect(src, contains('sync_loan_schedule_penalties'));
      expect(src, contains('v_total_payable + v_penalties - v_scheduled'));
      expect(src, contains('ls.installment_number DESC'));
      expect(src, contains('SET amount_due = ROUND(amount_due + v_gap, 2)'));
    });

    test('term-end penalty sweep ay nag-sysync sa schedule', () {
      final src = _squash(
          _read('supabase/migrations/00190_penalty_into_installments.sql'));
      expect(src, contains('PERFORM public.sync_loan_schedule_penalties'));
      expect(src, contains('apply_loan_term_penalties'));
    });

    test('backfill ng lumang penalties', () {
      final src = _squash(
          _read('supabase/migrations/00190_penalty_into_installments.sql'));
      expect(src, contains('SELECT DISTINCT pl.loan_id'));
    });

    test('manual apply-penalty (loans-manage) ay nag-sysync din', () {
      final src = _read('supabase/functions/loans-manage/index.ts');
      expect(src, contains("db.rpc('sync_loan_schedule_penalties'"));
      expect(src, contains('p_loan_id: loan_id'));
    });

    test('bagong schedule ay nag-sysync kapag may penalty na', () {
      final src = _read('supabase/functions/_shared/loan_schedules.ts');
      expect(src, contains("db.rpc('sync_loan_schedule_penalties'"));
      expect(src, contains('p_loan_id: loan.id'));
    });
  });
}
