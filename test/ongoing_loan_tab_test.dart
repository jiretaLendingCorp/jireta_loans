// test/ongoing_loan_tab_test.dart
//
// ONGOING LOAN TAB ng Loan Records (`/hm/loan-records/ongoing`)
//
// ANO ANG TINITIGNAN NITO
//   • Ang Ongoing Loan tab ay para lang sa mga loan na TALAGANG ongoing —
//     `active` lang. HINDI kasama ang `approved` (hindi pa na-release),
//     `overdue`, at `completed`.
//   • Unang bukas ng `/ongoing` (refresh / deep link / bookmark): 'all' ang
//     default ng provider, kaya kailangang i-sync ang tab mula sa URL. Dati,
//     hindi ito nangyayari — lahat ng loan (overdue at completed kasama) ang
//     lumalabas sa Ongoing Loan tab.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/providers/hm_loan_provider.dart';

// ── Fake: itinatala lang ang natanggap na `status` params ────────────────────

class _FakeLoanDs implements LoanRemoteDataSource {
  int calls = 0;
  final List<String?> statuses = [];

  @override
  Future<Map<String, dynamic>> getList({
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    String? lenderId,
    String? dateFrom,
    String? dateTo,
  }) async {
    calls++;
    statuses.add(status);
    return {'data': const [], 'meta': const {}};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hinihintay ang async na initial fetch ng notifier.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

String _readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

void main() {
  group('Ongoing Loan tab: active lang ang hinihingi', () {
    test('unang bukas sa /ongoing — i-sync ang tab mula sa URL', () async {
      final ds = _FakeLoanDs();
      final notifier = HmLoanNotifier(ds);
      await _flush();
      // Ito ang default ng provider (All) bago ma-sync sa URL.
      expect(ds.statuses, [null]);

      notifier.syncTab('active');
      await _flush();

      expect(ds.statuses.last, 'active');
      notifier.dispose();
    });

    test('hindi kasama ang approved, overdue, at completed', () async {
      final ds = _FakeLoanDs();
      final notifier = HmLoanNotifier(ds);

      notifier.syncTab('active');
      await _flush();

      expect(ds.statuses.last, 'active',
          reason: 'Hindi pa ongoing ang approved (wala pang release)');
      notifier.dispose();
    });

    test('hindi kasama ang overdue at completed', () async {
      final ds = _FakeLoanDs();
      final notifier = HmLoanNotifier(ds);

      notifier.syncTab('active');
      await _flush();

      final status = ds.statuses.last ?? '';
      expect(status, isNot(contains('overdue')));
      expect(status, isNot(contains('completed')));
      notifier.dispose();
    });

    test('hindi nagre-reload kapag tugma na ang tab', () async {
      final ds = _FakeLoanDs();
      final notifier = HmLoanNotifier(ds);

      notifier.syncTab('active');
      await _flush();
      final before = ds.calls;

      notifier.syncTab('active');
      await _flush();

      expect(ds.calls, before);
      notifier.dispose();
    });
  });

  group('Naka-wire ang screen sa syncTab (HM + Employee)', () {
    test('ang tab mula sa URL ang ini-apply sa loan list', () {
      for (final path in const [
        'lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart',
        'lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart',
      ]) {
        final src = _readNormalized(path);
        // Unang build: ipinagpapaliban sa post-frame ang sync (bawal mag-modify
        // ng provider habang nagbi-build), tapos `syncTab` ang tumatakbo.
        expect(src, contains('addPostFrameCallback'),
            reason: '$path: kailangang ma-sync ang tab pagkatapos ng frame');
        expect(src, contains('hmLoanProvider.notifier).syncTab('),
            reason: '$path: kailangang i-sync ang tab mula sa URL');
      }
    });
  });
}
