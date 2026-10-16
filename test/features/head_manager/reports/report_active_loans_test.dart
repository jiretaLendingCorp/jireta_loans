// test/features/head_manager/reports/report_active_loans_test.dart
//
// LOAN RECORDS ng Reports page: ACTIVE loans lang ang nakalagay.
//
// Ang `interest_report` ng `reports-generate` ay ibinabalik ang LAHAT ng loan sa
// napiling period (walang status filter sa server), kaya sa app mismo sinasala
// ang rows bago ipasa sa Loan Records section — active lang ang nasa table,
// summary cards, at Export.
//
// Sinusuri dito ang `activeLoanRecords()`:
//   * active lang ang isinasama,
//   * hindi kasama ang rejected / completed / overdue / pending / iba pa,
//   * hindi kasama ang blangko o `N/A` (walang status) na row,
//   * hindi case-sensitive (hal. `Active` / `ACTIVE`).

import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/features/head_manager/reports/screens/hm_report_library_screen.dart';

Map<String, dynamic> row(String number, Object? status) => {
      'loanNumber': number,
      'lenderName': 'Juan Dela Cruz',
      'principalAmount': 10000,
      'interestAmount': 2000,
      'totalPayable': 12000,
      'status': status,
    };

void main() {
  group('activeLoanRecords', () {
    test('active lang ang isinasama sa Loan Records', () {
      final rows = [
        row('LN-1', 'active'),
        row('LN-2', 'rejected'),
        row('LN-3', 'overdue'),
        row('LN-4', 'active'),
        row('LN-5', 'completed'),
      ];

      final out = activeLoanRecords(rows);

      expect(out.map((r) => r['loanNumber']).toList(), ['LN-1', 'LN-4']);
      // Buo pa rin ang row (hindi ito bagong hugis) para sa table at export.
      expect(out.first['totalPayable'], 12000);
      expect(out.first.keys.toList(), rows.first.keys.toList());
    });

    test('walang status (blangko / N/A) ay hindi kasama', () {
      final rows = [
        row('LN-1', null),
        row('LN-2', ''),
        row('LN-3', '   '),
        row('LN-4', 'N/A'),
        row('LN-5', 'active'),
      ];

      expect(activeLoanRecords(rows).map((r) => r['loanNumber']).toList(),
          ['LN-5']);
    });

    test('hindi case-sensitive ang status', () {
      final rows = [
        row('LN-1', 'Active'),
        row('LN-2', 'ACTIVE'),
        row('LN-3', 'Rejected'),
      ];

      expect(activeLoanRecords(rows).map((r) => r['loanNumber']).toList(),
          ['LN-1', 'LN-2']);
    });

    test('walang active sa period → blangko ang listahan', () {
      expect(activeLoanRecords([row('LN-1', 'completed')]), isEmpty);
      expect(activeLoanRecords(const []), isEmpty);
    });
  });
}
