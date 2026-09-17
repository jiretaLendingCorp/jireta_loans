// test/walkin_loan_linkage_test.dart
//
// BUSINESS RULE: ang isang walk-in (In-Office) application ay dapat may
// naka-link na loan sa sandaling may loan na si lender — at hindi na dapat
// lumabas sa In-Office tab ng Loan Records ang mga DRAFT.
//
// BUG NA NAAYOS
//   • In-Office tab ng Loan Records: "No loan yet" pa rin kahit ACTIVE na ang
//     loan. Dahilan: ang Step-3 submit (`in-office-view?fn=submit-account`)
//     ay nagse-set ng status 'submitted' + auto-verified account pero WALANG
//     loan (tuloy ang lender sa app). Ang auto-convert (kyc-view) ay
//     tumatakbo lang kapag may KYC verification event — wala na iyon dahil
//     auto-verified na. At ang `loans-apply` (lender self-apply) ay hindi
//     nagli-link pabalik sa walk-in application.
//   • Ang mga DRAFT (kasama ang abandonadong wizard — may draft row agad pag
//     tap ng "New Walk-in") ay nakalista rin sa parehong tab.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('loans-apply: walk-in application linkage', () {
    late final String src = _read('supabase/functions/loans-apply/index.ts');

    test('nagli-link ng bagong loan sa pending walk-in application', () {
      expect(src.contains("from('in_office_applications')"), isTrue);
      expect(src.contains("in_office_application_id: appId"), isTrue,
          reason: 'dapat i-link ang loan sa walk-in app');
    });

    test('hindi ginagalaw ang application na may loan na', () {
      expect(src.contains(".eq('in_office_application_id', appId)"), isTrue,
          reason: 'i-skip ang app na may naka-link nang loan');
    });

    test('i-mark na converted ang naka-link na application', () {
      expect(src.contains("status: 'converted', wizard_step: 5"), isTrue);
    });
  });

  group('In-Office tab: walang draft', () {
    test('Head Manager tab ay nagsasala ng draft', () {
      final src = _read(
          'lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart');
      expect(src.contains("_filteredInOffice"), isTrue);
      expect(src.contains("!= 'draft'"), isTrue,
          reason: 'draft applications ay hindi dapat nakalista sa tab');
    });

    test('Employee tab ay nagsasala rin ng draft', () {
      final src = _read(
          'lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart');
      expect(src.contains("!= 'draft'"), isTrue);
    });

    test('ang draft filter ay bago ang search filter (count chip tama)', () {
      final src = _read(
          'lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart');
      final draftIdx = src.indexOf("!= 'draft'");
      final searchIdx = src.indexOf('_inOfficeSearch.isEmpty) return visible');
      expect(draftIdx, greaterThan(0));
      expect(searchIdx, greaterThan(draftIdx),
          reason:
              'dapat salain muna ang draft bago ang search para ang bilang sa chip ay tama');
    });
  });

  group('Migration 00167: data repair', () {
    late final String sql =
        _read('supabase/migrations/00167_walkin_app_loan_linkage.sql');

    test('i-link ang existing loan ng lender sa stuck na application', () {
      expect(sql.contains('in_office_application_id = c.app_id'), isTrue);
      expect(sql.contains("a.status = 'submitted'"), isTrue);
    });

    test('i-mark converted ang application na may loan na', () {
      expect(sql.contains("SET status      = 'converted'"), isTrue);
      expect(sql.contains('WHERE l.in_office_application_id = a.id'), isTrue);
    });

    test('idempotent + may index sa link column', () {
      expect(sql.contains('NOT EXISTS ('), isTrue,
          reason: 'huwag i-link muli ang app na may loan na');
      expect(
          sql.contains(
              'CREATE INDEX IF NOT EXISTS idx_loans_in_office_application_id'),
          isTrue);
    });
  });
}
