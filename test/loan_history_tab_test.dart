// test/loan_history_tab_test.dart
//
// PREVIOUS LOAN TAB ng Loan Records (`loans-view?fn=get-history`)
//
// ANO ANG TINITIGNAN NITO
//   • Ang listahan ay TANGING para sa mga loan na TAPOS nang bayaran
//     (`completed`, o outstanding 0) — hindi kasama ang ongoing/"for
//     completion". Server-side ang filter (`get-history`, DERIVED ang
//     outstanding balance), kaya `get-history` ang tinatawag, hindi `get-list`.
//   • Ang toolbar (search + Filter Date) ay naka-wire sa SARILING provider ng
//     tab: dati, ang bawat bagong tab ay kailangang isa-isang ikabit, at ang
//     nakalimutang ikabit ay tahimik na hindi gumagana (walang filter na
//     nangyayari).
//   • Ang pag-CLEAR ng date filter (×): `copyWith(dateFrom: null)` ay kailangang
//     TALAGANG mag-clear — kung `??` lang ang gamit, `null ?? oldValue` =
//     oldValue at nananatiling filtered ang query.
//   • Ang progress/total-paid/last-payment na datos ay galing sa payload
//     (`payments_total`, `progress`, `last_payment_at`) at handa para sa table.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/data/models/loan_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/providers/hm_loan_history_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/widgets/loan_details_side_panel.dart';

// ── Fake: itinatala lang ang natanggap na params at ang isinasagot na payload ──

class _FakeHistoryDs implements LoanRemoteDataSource {
  int calls = 0;
  int? page;
  int? limit;
  String? search;
  String? dateFrom;
  String? dateTo;
  Map<String, dynamic> response = const {'data': [], 'meta': {}};

  /// Kapag naka-set, hinihintay muna ito bago magbalik — para ma-observe ang
  /// loading state habang nag-a-apply ng filter.
  Future<void>? gate;

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
    if (gate != null) await gate;
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

/// Payload ng `loans-view?fn=get-details` — sapat para mabuo ang side panel.
Map<String, dynamic> _detailsPayload() => {
      'id': 'loan-1',
      'loan_number': 'LN-2025-0012',
      // Bayad na pero `active` pa ang hilaw na status → dapat Completed pa rin.
      'status': 'active',
      'principal_amount': 50000,
      'interest_rate': 20,
      'total_payable': 60000,
      'outstanding_balance': 0,
      'installment_amount': 2500,
      'payment_frequency': 'monthly',
      'term_periods': 3,
      'disbursed_at': '2025-05-10T02:24:00.000Z',
      'created_at': '2025-05-10T02:24:00.000Z',
      'updated_at': '2025-08-10T01:15:00.000Z',
      'lender': {
        'first_name': 'Maria',
        'middle_name': 'Santos',
        'last_name': 'Dela Cruz',
        'phone_number': '+63 917 555 1234',
        'email': 'maria@example.com',
      },
      'lender_address': {
        'street': '123 Mabini St.',
        'barangay': 'Poblacion',
        'city': 'Makati',
        'province': 'Metro Manila',
        'zip_code': '1210',
      },
      'loan_schedules': [
        {
          'installment_number': 1,
          'due_date': '2025-05-10',
          'amount_due': 2500,
          'status': 'paid',
          'paid_at': '2025-05-10T04:00:00.000Z',
        },
        {
          'installment_number': 2,
          'due_date': '2025-06-10',
          'amount_due': 2500,
          'status': 'paid',
          'paid_at': '2025-06-10T04:00:00.000Z',
        },
        {
          'installment_number': 3,
          'due_date': '2025-07-10',
          'amount_due': 2500,
          'status': 'paid',
          'paid_at': '2025-07-10T04:00:00.000Z',
        },
      ],
      'payments': [
        {
          'amount': 2500,
          'status': 'verified',
          'payment_method': 'gcash',
          'reference_number': 'GCB-123456',
          'paid_at': '2025-05-10T04:00:00.000Z',
          'created_at': '2025-05-10T04:00:00.000Z',
        },
      ],
      'disbursements': [
        {
          'disbursed_at': '2025-05-10T02:24:00.000Z',
          'xendit_id': 'TRX-20250510-0012',
        },
      ],
    };

// ── Source guards ─────────────────────────────────────────────────────────────

const _hmScreen =
    'lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart';
const _empScreen =
    'lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart';
const _panelFile =
    'lib/presentation/features/head_manager/loans/widgets/loan_details_side_panel.dart';

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

        // Full-width na ang table (nasa itaas na ang filter bar), kaya 880
        // ang minimum — kapareho ng ibang desktop tables sa screen.
        expect(block, contains('minTableWidth: 880,'),
            reason: 'Bumabalik sa stacked cards sa desktop viewport');
        expect(block, contains('rowHeight: 64,'));
      });

      test('${screen.split('/').last}: may sapat na lapad ang Status column',
          () {
        final block = _historyBlock(_readNormalized(screen));

        // 'Completed' (~70px) ang pinakamahabang status sa Previous Loan tab.
        // Flex 4 ang Status para hindi ito ma-clip sa 880px na table.
        expect(block,
            contains("ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 4)"));
      });

      test('${screen.split('/').last}: naka-Previous Loans design ang layout',
          () {
        final block = _historyBlock(_readNormalized(screen));

        // Stat cards sa itaas ng table.
        for (final label in const [
          "title: 'Total Loans'",
          "title: 'Completed'",
          "title: 'Ongoing'",
          "title: 'Overdue'",
        ]) {
          expect(block, contains(label));
        }

        // Bare na filter bar sa itaas ng table: search + date + apply.
        // Wala nang "Search & Filter" title at malaking card wrapper.
        expect(block, isNot(contains('Search & Filter')));
        expect(block, contains('Search by Loan ID or client name...'));
        expect(block, contains('Apply Filters'));
        // Tinanggal ang asul na "Loan Details" info card sa ibaba ng table.
        expect(block, isNot(contains('_buildHistoryDetailsCard')));
        expect(block, contains('Showing \$from - \$to of \$total'));

        // Mga column ng design (walang progress column sa Previous Loans).
        // Walang hiwalay na Client Name column — nasa ILALIM ng Loan ID ang
        // pangalan para buo ang Loan ID.
        expect(block, isNot(contains("ResponsiveCol('Client Name'")));
        expect(block, contains('lenderName.isEmpty'));
        for (final col in const [
          'Loan ID',
          'Amount',
          'Term',
          'Installment',
          'Start Date',
          'End Date',
          'Status',
        ]) {
          expect(block, contains("ResponsiveCol('$col'"));
        }
      });

      test('${screen.split('/').last}: Apply button lang ang naglo-load', () {
        final block = _historyBlock(_readNormalized(screen));

        // Ang buong-table shimmer ay para lang sa UNANG load.
        expect(block, contains('if (st.isLoading && !st.hasLoaded)'));
        expect(block, contains('_buildHistoryFilterCard(st)'));
        // Spinner sa loob ng Apply button habang nag-a-apply.
        expect(block, contains('onPressed: st.isLoading ? null'));
        expect(block, contains('CircularProgressIndicator'));
      });

      test('${screen.split('/').last}: may Previous Loan pill tab', () {
        final src = _readNormalized(screen);
        // "Loan History" ang dating label; "Previous Loan" na ngayon sa UI.
        expect(src, contains("FilterTabDef('loan_history', 'Previous Loan'"));
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

  group('Source guard: hidden na ang Completed tab', () {
    test('HM at Employee: wala nang Completed pill', () {
      for (final screen in {_hmScreen, _empScreen}) {
        final src = _readNormalized(screen);
        expect(src, isNot(contains("'completed', 'Completed'")));
        expect(src, contains("'loan_history', 'Previous Loan'"));
      }
    });

    test('lumang /completed URL: redirect sa Previous Loan', () {
      final router = _readNormalized('lib/core/router/app_router.dart')
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(
          router,
          contains(
              'path: RouteConstants.hmLoanRecordsCompleted, redirect: (ctx, s) => RouteConstants.hmLoanApplicationsHistory'));
      expect(
          router,
          contains(
              'path: RouteConstants.empLoansCompleted, redirect: (ctx, s) => RouteConstants.empLoansHistory'));
    });
  });

  group('Source guard: completed lang ang laman ng Previous Loan', () {
    test('get-history: outstanding <= 0 lang (wala nang for-completion)', () {
      final src = _readNormalized('supabase/functions/loans-view/index.ts');
      expect(src, contains('return outstanding <= 0;'),
          reason: 'bayad nang loan lang ang dapat isama');
      expect(src, isNot(contains('outstanding <= (installment')),
          reason: 'dati itong "malapit nang matapos" — ongoing pa ang mga ito');
    });
  });

  group('Previous Loan: for-completion (ongoing) ay hindi kasama', () {
    test('client filter + count ay tugma sa completed rows', () async {
      final ds = _FakeHistoryDs();
      ds.response = {
        'data': [
          _historyRow(), // completed
          _historyRow(
            status: 'active',
            outstanding: 20000,
            paymentsTotal: 40000,
            progress: 0.6667,
            completionState: 'for_completion',
          ),
        ],
        'meta': {'page': 1, 'total_pages': 1, 'total': 2},
      };
      final notifier = HmLoanHistoryNotifier(ds);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.loans, hasLength(1));
      expect(notifier.state.loans.single.status, 'completed');
      expect(notifier.state.totalCount, 1);
    });

    test('bayad na pero `active` ang hilaw na status ay kasama pa rin', () async {
      final ds = _FakeHistoryDs();
      ds.response = {
        'data': [
          _historyRow(status: 'active', outstanding: 0, progress: 1),
        ],
        'meta': {'page': 1, 'total_pages': 1, 'total': 1},
      };
      final notifier = HmLoanHistoryNotifier(ds);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.loans, hasLength(1));
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

    test('hasLoaded: false habang first load, true pagkatapos', () async {
      final ds = _FakeHistoryDs();
      ds.response = {
        'data': [_historyRow()],
        'meta': {'page': 1, 'total_pages': 1, 'total': 1},
      };
      final notifier = HmLoanHistoryNotifier(ds);

      // Dito pa lang Naglo-load: shimmer ang tama, hindi blangkong table.
      expect(notifier.state.hasLoaded, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.hasLoaded, isTrue);
    });

    test('filter reload: hindi binubura ang table habang naglo-load', () async {
      final ds = _FakeHistoryDs();
      ds.response = {
        'data': [_historyRow()],
        'meta': {'page': 1, 'total_pages': 1, 'total': 1},
      };
      final notifier = HmLoanHistoryNotifier(ds);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.loans, hasLength(1));

      // Slow request para ma-observe ang loading state.
      final gate = Completer<void>();
      ds.gate = gate.future;
      notifier.setSearch('april');

      expect(notifier.state.isLoading, isTrue);
      expect(notifier.state.hasLoaded, isTrue);
      expect(notifier.state.loans, hasLength(1),
          reason: 'dapat hindi mawala ang table habang nag-a-apply');

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isLoading, isFalse);
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
    });    test('out-of-range na progress ay kino-clamp sa 0..1', () {
      expect(LoanModel.fromJson(_historyRow(progress: 1.4)).progress, 1);
      expect(LoanModel.fromJson(_historyRow(progress: -0.2)).progress, 0);
    });
  });

  group('Loan Details side panel (View ng Previous Loan)', () {
    test('HM at Employee: ang View button ay nagbubukas ng side panel', () {
      for (final screen in {_hmScreen, _empScreen}) {
        final src = _readNormalized(screen);
        expect(src, contains('loan_details_side_panel.dart'));
        expect(
            src,
            contains(
                'showLoanDetailsSidePanel(context, loanId: loan.id, loan: loan)'));
        expect(src, isNot(contains('showHmLoanHistoryModal')),
            reason: 'gitnang dialog dati — side panel na ngayon');
        expect(
            src, contains('onPressed: () => _openLoanDetails(context, loan)'),
            reason: 'View button ng Previous Loan table');
        expect(src, contains('onTap: () => _openLoanDetails(context, loan)'),
            reason: 'row tap — pareho ang bukas na panel');
      }
    });

    test('panel: naka-slide mula kanan at kumpleto ang sections', () {
      final src = _readNormalized(_panelFile);
      expect(src, contains('Alignment.centerRight'));
      expect(src, contains('begin: const Offset(1, 0)'),
          reason: 'slide-in mula sa kanan');
      // Mas malapad (560) para hindi maputol ang address at history.
      expect(src, contains('560.0'));
      expect(src, contains('thumbVisibility: true'),
          reason: 'dapat may visible scrollbar — hindi mukhang naputol');
      for (final label in const [
        "'Loan ID'",
        "'Client Information'",
        "'Client Name'",
        "'Phone Number'",
        "'Email'",
        "'Address'",
        "'Loan Information'",
        "'Term'",
        "'Installment Amount'",
        "'Start Date'",
        "'End Date'",
        "'Approval Date'",
        "'Completion Date'",
        "'Transaction Reference'",
        "'Payment Schedule'",
        "'Due Date'",
        "'Paid Date'",
        "'Payment History'",
        "'Date & Time'",
        "'Successful'",
        "'Notes'",
        "'Download Receipt'",
      ]) {
        expect(src, contains(label));
      }
    });

    testWidgets('lumalabas sa KANAN at tama ang nilalaman', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late BuildContext hostContext;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          hostContext = context;
          return const Scaffold(body: SizedBox.expand());
        }),
      ));

      showLoanDetailsSidePanel(
        hostContext,
        loanId: 'loan-1',
        loadDetails: (_) async => _detailsPayload(),
      );
      await tester.pumpAndSettle();

      // Nasa KANAN ng screen — hindi gitna (dating dialog).
      final rect = tester.getRect(find.byType(LoanDetailsSidePanel));
      expect(rect.right, 1400);
      expect(rect.left, closeTo(840, 1));

      // Loan ID + status (bayad na kahit `active` pa ang hilaw).
      expect(find.text('Loan Details'), findsOneWidget);
      expect(find.text('LN-2025-0012'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      // Financial summary — apat sa isang row.
      expect(find.text('Loan Amount'), findsOneWidget);
      expect(find.text('₱50,000'), findsOneWidget);
      expect(find.text('Total Amount Payable'), findsOneWidget);
      expect(find.text('(20% flat rate)'), findsOneWidget);
      expect(find.text('₱60,000'), findsOneWidget);
      expect(find.text('Total Amount Paid'), findsOneWidget);
      expect(find.text('Remaining Balance'), findsOneWidget);
      expect(find.text('₱0'), findsOneWidget);

      // Client Information.
      expect(find.text('Client Information'), findsOneWidget);
      expect(find.text('Maria Santos Dela Cruz'), findsOneWidget);
      expect(find.text('+63 917 555 1234'), findsOneWidget);
      expect(find.text('maria@example.com'), findsOneWidget);
      expect(
          find.text('123 Mabini St., Poblacion, Makati, Metro Manila, 1210'),
          findsOneWidget);

      // Loan Information.
      expect(find.text('Loan Information'), findsOneWidget);
      expect(find.text('3 months (Monthly)'), findsOneWidget);
      expect(find.text('TRX-20250510-0012'), findsOneWidget);

      // Payment Schedule + Payment History.
      expect(find.text('Payment Schedule'), findsOneWidget);
      expect(find.text('Paid'), findsNWidgets(3));
      expect(find.text('Payment History'), findsOneWidget);
      expect(find.text('Successful'), findsOneWidget);
      expect(find.text('GCB-123456'), findsOneWidget);

      // Notes + Download Receipt.
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Loan fully paid. No outstanding balance.'),
          findsOneWidget);
      expect(find.text('Download Receipt'), findsOneWidget);
    });

    testWidgets('bigong load: may error at gumagana ang Retry', (tester) async {
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LoanDetailsSidePanel(
            loanId: 'loan-1',
            loadDetails: (_) async {
              calls++;
              if (calls == 1) throw Exception('boom');
              return _detailsPayload();
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load loan details.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Loan Information'), findsOneWidget);
    });
  });
}
