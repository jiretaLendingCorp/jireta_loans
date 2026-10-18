// test/lender_quick_reapply_test.dart
//
// 2-STEP RE-APPLY (returning lender)
//
// ANO ANG TINITIGNAN NITO
//   • Kapag may BAYAD NANG loan (`completed`, o fully paid) ang lender, ang
//     apply flow ay Purpose → Loan Amount → Submit na lang — hindi na ang
//     5-step wizard (financial, co-maker, signature, review).
//   • Kapag wala pang bayad na loan, null ang trigger kaya normal wizard pa rin.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/models/loan_model.dart';
import 'package:jireta_loans/presentation/features/lender/loans/screens/lender_apply_loan_screen.dart';

LoanModel _loan({
  String id = 'loan-1',
  String status = 'completed',
  num outstanding = 0,
}) =>
    LoanModel.fromJson({
      'id': id,
      'loan_number': 'LN-$id',
      'lender_id': 'lender-1',
      'principal_amount': 10000,
      'interest_rate': 0,
      'interest_amount': 1000,
      'total_payable': 11000,
      'outstanding_balance': outstanding,
      'payment_frequency': 'daily',
      'term_days': 60,
      'term_periods': 60,
      'status': status,
      'created_at': '2026-09-01T02:00:00Z',
      'updated_at': '2026-09-27T07:00:00Z',
    });

String _readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

void main() {
  group('latestCompletedLoan: kailan naka-2-step ang re-apply', () {
    test('may completed loan → 2-step re-apply', () {
      final loans = [_loan(id: '2'), _loan(id: '1')];
      expect(latestCompletedLoan(loans)?.id, '2',
          reason: 'pinakabago (unang row) ang gagamitin');
    });

    test('walang bayad na loan → normal na wizard', () {
      expect(
        latestCompletedLoan([
          _loan(id: 'p', status: 'pending'),
          _loan(id: 'a', status: 'approved'),
        ]),
        isNull,
      );
      expect(latestCompletedLoan(const []), isNull);
    });

    test('active/overdue na ubos ang balanse → bayad na rin', () {
      expect(
        latestCompletedLoan([_loan(status: 'active', outstanding: 0)])?.id,
        'loan-1',
      );
    });

    test('active na may natitirang balanse → hindi pa re-apply', () {
      expect(
        latestCompletedLoan([_loan(status: 'active', outstanding: 5000)]),
        isNull,
      );
    });
  });

  group('Source guards: 2-step na flow', () {
    late String src;

    setUpAll(() {
      src = _readNormalized(
          'lib/presentation/features/lender/loans/screens/lender_apply_loan_screen.dart');
    });

    test('gumagamit ang wizard ng quick content kapag may completed loan', () {
      expect(src, contains('latestCompletedLoan(loans)'));
      expect(src,
          contains('_buildQuickApplyContent(fmt, loanState.schedulePreview, false)'));
      // "Loan Details" lang ang header — walang step chip/subtitle.
      expect(src, contains("child: const Text('Loan Details'"));
      expect(src, isNot(contains("'Step 2 of 2'")));
      // Step 2 = Loan Details (pwedeng pumili ng frequency at term),
      // naka-center sa desktop sa 960px max width.
      expect(src,
          contains('_buildLoanDetailsStep(fmt, preview, isSubmitting)'));
      expect(src, contains('maxWidth: 960'));
      // Desktop: walang floating nav → walang makapal na blangkong banda sa
      // ilalim ng Back/Submit buttons.
      expect(src, contains('width >= kDesktopBreakpoint) return 16;'));
    });

    test('desktop layout: naka-center at 2 columns ang purpose picker', () {
      // Hindi naka-stretch sa buong browser ang content sa desktop view.
      expect(src, contains('class _CenteredMaxWidth extends StatelessWidget'));
      expect(src, contains('maxWidth: 960'));
      // Desktop (>= 720px na loob ng centered column) → 2 columns.
      expect(src, contains('if (c.maxWidth < 720)'));
      expect(src, contains('spacing: 12,'));
      // Right-aligned ang Continue button sa desktop.
      expect(src, contains('alignment: Alignment.centerRight'));
      // Walang title header sa purpose screen.
      expect(src, isNot(contains("'Choose Purpose'")));
    });

    test('ang quick submit ay amount/frequency/purpose lang ang ipinapadala',
        () {
      final start = src.indexOf('Future<void> _submitQuickApply(');
      final end = src.indexOf('Future<bool> _confirmAndAuthenticate(');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final quick = src.substring(start, end);

      expect(quick, contains('amount: _amount'));
      expect(quick, contains('frequency: _frequency'));
      expect(quick, contains('termPeriods: _termPeriods'));
      expect(quick, contains('purpose: _purposeCtrl.text.trim()'));
      // Wala nang co-maker/financial/emergency sa quick re-apply.
      expect(quick, isNot(contains('coMaker:')));
      expect(quick, isNot(contains('employment:')));
      expect(quick, isNot(contains('emergencyContacts:')));
    });
  });
}
