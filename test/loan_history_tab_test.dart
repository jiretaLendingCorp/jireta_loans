// test/loan_history_tab_test.dart
//
// LOAN HISTORY TAB ng Loan Records (`loans-view?fn=get-history`)
//
// ANO ANG TINITIGNAN NITO
//   • Ang listahan ay para sa mga lender na TAPOS nang bayaran (`completed`) at
//     sa mga MALAPIT nang matapos (isang installment na lang ang natitira) —
//     kaya `get-history` (server-side ang filter, DERIVED ang outstanding
//     balance) ang tinatawag, hindi `get-list`.
//   • Ang toolbar (search + Filter Date) ay naka-wire sa SARILING provider ng
//     tab: dati, ang bawat bagong tab ay kailangang isa-isang ikabit, at ang
//     nakalimutang ikabit ay tahimik na hindi gumagana (walang filter na
//     nangyayari).
//   • Ang pag-CLEAR ng date filter (×): `copyWith(dateFrom: null)` ay kailangang
//     TALAGANG mag-clear — kung `??` lang ang gamit, `null ?? oldValue` =
//     oldValue at nananatiling filtered ang query.
//   • Ang progress/total-paid/last-payment na datos ay galing sa payload
//     (`payments_total`, `progress`, `last_payment_at`) at handa para sa table.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/data/models/loan_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/providers/hm_loan_history_provider.dart';

// ── Fake: itinatala lang ang natanggap na params at ang isinasagot na payload ──

class _FakeHistoryDs implements LoanRemoteDataSource {
  int calls = 0;
  int? page;
  int? limit;
  String? search;
  String? dateFrom;
  String? dateTo;
  Map<String, dynamic> response = const {'data': [], 'meta': {}};

  @override
  Future<Map<String, dynamic>> getHistory({
    int page = 1,
    int limit = 10,
    String? search,
    String? dateFrom,
    String? dateTo,
  }) async {
    calls++;
    this.page = page;
    this.limit = limit;
    this.search = search;
    this.dateFrom = dateFrom;
    this.dateTo = dateTo;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _from = '2026-08-31T16:00:00.000Z'; // Manila Sep 1, 00:00
const _to = '2026-09-07T15:59:59.999Z'; // Manila Sep 7, 23:59:59.999

/// Payload shape na ibinabalik ng `loans-view?fn=get-history`.
Map<String, dynamic> _historyRow({
  String status = 'completed',
  num outstanding = 0,
  num paymentsTotal = 60000,
  num totalPayable = 60000,
  num progress = 1,
  String completionState = 'completed',
  String? lastPaymentAt = '2026-09-25T06:29:00.000Z',
}) =>
    {
      'id': 'loan-1',
      'loan_number': 'LN-2026-760880',
      'lender_id': 'lender-1',
      'lender_name': 'April Malasan',
      'principal_amount': 50000,
      'interest_rate': 20,
      'total_payable': totalPayable,
      'payments_total': paymentsTotal,
      'outstanding_balance': outstanding,
      'progress': progress,
      'installment_amount': 5000,
      'payment_frequency': 'monthly',
      'status': status,
      'completion_state': completionState,
      'last_payment_at': lastPaymentAt,
      'disbursed_at': '2026-09-23T04:57:00.000Z',
      'created_at': '2026-09-01T04:00:00.000Z',
      'updated_at': '2026-09-25T04:00:00.000Z',
    };

// ── Source guards ─────────────────────────────────────────────────────────────

const _hmScreen =
    'lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart';
const _empScreen =
    'lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart';

/// Read a repo file and normalize line endings (Windows checkouts use CRLF).
String _readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

/// Ang buong Loan History UI (section + table + pagination) ng isang screen.
/// Nasa pagitan ito ng mga kalapit na builder para hindi maisama ang ibang
/// bahagi ng screen (na may role-specific na `RouteConstants`).
String _historyBlock(String source) {
  final start = source.indexOf('Widget _buildLoanHistorySection(');
  final end = source.indexOf('Widget _buildInOfficeList(');
  expect(start, greaterThanOrEqualTo(0), reason: 'walang Loan History section');
  expect(end, greaterThan(start), reason: 'hindi mahanap ang dulo ng block');
  // Isang linya ang bawat declaration pagkatapos nito (nawawala ang indent at
  // line breaks), kaya ang `contains()` ay hindi dipende sa formatting.
  return source
      .substring(start, end)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

void main() {
  group('Source guards: naka-table at walang overlap ang Loan History', () {
    for (final screen in {_hmScreen, _empScreen}) {
      test('${screen.split('/').last}: naka-table sa 880px pataas', () {
        final block = _historyBlock(_readNormalized(screen));

        // 880 = kapareho ng Disbursements tab ng parehong screen. Kapag mas
        // mataas dito (hal. 1120), bumabagsak sa stacked-card layout ang tab
        // kahit sa ~1080px na desktop viewport.
        expect(block, contains('minTableWidth: 880,'),
            reason: 'Bumabalik sa stacked cards sa desktop viewport');
        expect(block, contains('rowHeight: 64,'));
      });

      test('${screen.split('/').last}: may sapat na lapad ang Status column',
          () {
        final block = _historyBlock(_readNormalized(screen));

        // 'For Completion' (~108px kasama ang dot) ang pinakamahabang laman ng
        // table. Kapag flex 2 ang Status (at flex 3 ang Progress), dumadaan ito
        // sa Last Payment column at natatakpan ang petsa.
        expect(block,
            contains("ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 3)"));
        final progressFlex2 =
            block.contains("ResponsiveCol('Progress', flex: 2)") ||
                block.contains(
                    "ResponsiveCol('Progress', icon: Icons.trending_up_rounded, flex: 2)");
        expect(progressFlex2, isTrue,
            reason: 'Nasa Status ang dapat na dagdag na lapad, hindi sa Progress');
      });

      test('${screen.split('/').last}: may Loan History pill tab', () {
        final src = _readNormalized(screen);
        expect(src, contains("FilterTabDef('loan_history', 'Loan History'"));
        expect(src, contains('hmLoanHistoryProvider'),
            reason: 'Hindi naka-wire ang toolbar/date filter ng tab');
      });
    }

    test('HM at Employee: byte-identical ang Loan History block (sync rule)', () {
      expect(_historyBlock(_readNormalized(_empScreen)),
          _historyBlock(_readNormalized(_hmScreen)),
          reason:
              'Dapat kapareho ng HM ang Employee screen — i-run ang scripts/sync_employee_screens.py');
    });
  });

  group('Loan History: ang provider ang tumatanggap ng toolbar params', () {
    test('initial load ay walang search/date filter', () {
      final ds = _FakeHistoryDs();
      HmLoanHistoryNotifier(ds);

      expect(ds.calls, 1, reason: 'initial load');
      expect(ds.search, isNull);
      expect(ds.dateFrom, isNull);
      expect(ds.dateTo, isNull);
      expect(ds.limit, 10, reason: 'kaparehong page size ng Loan Records');
    });

    test('search ay umabot sa datasource', () {
      final ds = _FakeHistoryDs();
      final notifier = HmLoanHistoryNotifier(ds);

      notifier.setSearch('april');

      expect(ds.search, 'april');
    });

    test('date range ay umabot sa datasource at na-i-clear', () {
      final ds = _FakeHistoryDs();
      final notifier = HmLoanHistoryNotifier(ds);

      notifier.setDateRange(_from, _to);
      expect(ds.dateFrom, _from);
      expect(ds.dateTo, _to);

      // Pag-clear (×): hindi dapat manatili ang lumang dates sa query.
      notifier.setDateRange(null, null);
      expect(ds.dateFrom, isNull);
      expect(ds.dateTo, isNull);
    });

    test('pagination: page + meta ay naka-parse sa state', () async {
      final ds = _FakeHistoryDs();
      ds.response = {
        'data': [_historyRow()],
        'meta': {'page': 2, 'total_pages': 3, 'total': 25},
      };
      final notifier = HmLoanHistoryNotifier(ds);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.currentPage, 2);
      expect(notifier.state.totalPages, 3);
      expect(notifier.state.totalCount, 25);
      expect(notifier.state.loans.single.loanNumber, 'LN-2026-760880');

      await notifier.load(page: 3);
      expect(ds.page, 3);
    });

    test('copyWith: hindi ipinasa ≠ ipinasang null', () {
      const base = HmLoanHistoryState(dateFrom: _from, dateTo: _to);
      expect(base.copyWith(search: 'juan').dateFrom, _from,
          reason: 'hindi ipinasa — panatilihin (search/pagination)');
      expect(base.copyWith(dateFrom: null, dateTo: null).dateFrom, isNull,
          reason: 'ipinasang null — i-clear (pag-alis ng date filter)');
    });
  });

  group('Loan History: progress/total-paid ng row', () {
    test('completed na loan → Completed label at 100% progress', () {
      final loan = LoanModel.fromJson(_historyRow());

      expect(loan.totalPaid, 60000);
      expect(loan.progress, 1);
      expect(loan.isFullyPaid, isTrue);
      expect(loan.completionLabel, 'Completed');
      expect(loan.lastPaymentAt, isNotNull);
    });

    test('isang installment na lang → For Completion (hindi pa 100%)', () {
      final loan = LoanModel.fromJson(_historyRow(
        status: 'active',
        outstanding: 5000,
        paymentsTotal: 55000,
        progress: 0.9167,
        completionState: 'for_completion',
      ));

      expect(loan.isFullyPaid, isFalse);
      expect(loan.completionLabel, 'For Completion');
      expect(loan.progress, closeTo(0.9167, 0.0001));
      expect(loan.outstandingBalance, 5000);
    });

    test('bayad na pero `active` pa ang hilaw na status → Completed pa rin', () {
      final loan = LoanModel.fromJson(
        _historyRow(status: 'active', completionState: 'for_completion'),
      );

      expect(loan.outstandingBalance, 0);
      expect(loan.isFullyPaid, isTrue,
          reason: 'auto-complete ay hindi tumakbo pero tapos nang magbayad');
      expect(loan.completionLabel, 'Completed');
    });

    test('walang pang bayad → walang last payment date, hindi bloated progress', () {
      final loan = LoanModel.fromJson(_historyRow(
        status: 'active',
        outstanding: 60000,
        paymentsTotal: 0,
        progress: 0,
        completionState: 'for_completion',
        lastPaymentAt: null,
      ));

      expect(loan.lastPaymentAt, isNull);
      expect(loan.progress, 0);
      expect(loan.totalPaid, 0);
    });

    test('out-of-range na progress ay kino-clamp sa 0..1', () {
      expect(LoanModel.fromJson(_historyRow(progress: 1.4)).progress, 1);
      expect(LoanModel.fromJson(_historyRow(progress: -0.2)).progress, 0);
    });
  });
}
