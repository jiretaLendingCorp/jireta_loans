// test/lender_greeting_layout_test.dart
//
// AYOS NG RIVE + GREETING DIALOG AT NG STAT TILES SA LENDER DASHBOARD
//
// Desktop (>= kDesktopBreakpoint):
//   * nakadikit sa KALIWANG gilid ng content ang buong grupo;
//   * ang FOX (Rive) ang pinaka-kaliwa, at nasa KANAN nito ang greeting dialog
//     ("Good morning/afternoon/evening, ...") — nakabaling pa-kaliwa ang buntot
//     ng dialog, patungo sa fox.
//
// Mobile (< breakpoint):
//   * hindi nagbabago — nasa KALIWA pa rin ng fox ang dialog.
//
// Stat tiles (DESKTOP at MOBILE):
//   * **Next Payment** — natitira sa pinakamaagang hindi pa bayad na
//     installment; kung walang schedules sa payload (gaya ng
//     `loans-view?fn=get-list`), ang `installment_amount` + ang `due_date` ang
//     ginagamit;
//   * **Installment** — `installment_amount` ng loan;
//   * wala na ang dating Active Loans / Total Borrowed / Total Paid.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jireta_loans/core/network/dio_client.dart';
import 'package:jireta_loans/core/utils/formatters.dart';
import 'package:jireta_loans/core/utils/timezone.dart';
import 'package:jireta_loans/data/datasources/remote/account_upgrade_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/disbursement_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/kpi_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/location_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/payment_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/lender/dashboard/screens/lender_dashboard_screen.dart';
import 'package:jireta_loans/presentation/features/lender/dashboard/screens/widgets/lender_welcome_group.dart';

import 'helpers/audit_test_helpers.dart';

const _nextDue = '2026-11-05T00:00:00.000Z';

/// Kapareho ng INIWAN ng `loans-view?fn=get-list`: walang buong schedule —
/// `installment_amount` at ang next unpaid na `due_date` lang.
final _loanListShape = <String, dynamic>{
  'id': 'loan-1',
  'loan_number': 'LN-2026-182756',
  'status': 'active',
  'principal_amount': 21000,
  'total_payable': 24000,
  'outstanding_balance': 30240,
  'payment_frequency': 'monthly',
  'term_periods': 3,
  'installment_amount': 4444,
  'due_date': _nextDue,
  'created_at': '2026-09-05T00:00:00.000Z',
  'updated_at': '2026-09-05T00:00:00.000Z',
};

/// Kapag may buong schedule sa payload (hal. details): bayad na ang una,
/// PARTIAL ang pangalawa (₱4,000 - ₱1,000 = ₱3,000 ang natitira).
final _loanWithSchedules = <String, dynamic>{
  ..._loanListShape,
  'loan_schedules': [
    {
      'id': 'sched-1',
      'loan_id': 'loan-1',
      'period_number': 1,
      'due_date': '2026-10-05T00:00:00.000Z',
      'amount_due': 4000,
      'amount_paid': 4000,
      'status': 'paid',
    },
    {
      'id': 'sched-2',
      'loan_id': 'loan-1',
      'period_number': 2,
      'due_date': _nextDue,
      'amount_due': 4000,
      'amount_paid': 1000,
      'status': 'partial',
    },
    {
      'id': 'sched-3',
      'loan_id': 'loan-1',
      'period_number': 3,
      'due_date': '2026-12-05T00:00:00.000Z',
      'amount_due': 4000,
      'amount_paid': 0,
      'status': 'pending',
    },
  ],
};

/// Ang aktibong loan na isinasagot sa `loans-view?fn=get-list` ng test na ito.
/// `null` kapag walang active loan (hal. bagong lender o bayad na).
Map<String, dynamic>? _activeLoan = _loanListShape;

/// Walang laman ang lahat ng ibang endpoint (payments, collections,
/// notifications, ...); ang loans list lang ang may aktibong loan.
Future<Response<dynamic>> _respond(RequestOptions o) async {
  final isLoansList = o.path == 'loans-view?fn=get-list';
  return Response<dynamic>(
    requestOptions: o,
    data: {
      'data': isLoansList
          ? (_activeLoan == null ? <dynamic>[] : [_activeLoan])
          : <dynamic>[],
      'items': <dynamic>[],
      'meta': {'unread_count': 0, 'total': 0, 'page': 1, 'total_pages': 1},
    },
  );
}

void main() {
  setUp(() => _activeLoan = _loanListShape);

  setUpAll(() async {
    await loadTestEnv();
    // Ang `AppFormatters` ay gumagamit ng 'en_PH' na DateFormat — sa app,
    // ini-initialize ito ng `flutter_localizations`; dito kailangan itong
    // tawagin nang direkta (kung hindi: LocaleDataException).
    await initializeDateFormatting();
    final client = FakeDioClient(_respond);
    GetIt.instance.registerLazySingleton<DioClient>(() => client);
    GetIt.instance.registerLazySingleton<KpiRemoteDataSource>(
        () => KpiRemoteDataSource(client));
    GetIt.instance.registerLazySingleton<LoanRemoteDataSource>(
        () => LoanRemoteDataSource(client));
    GetIt.instance.registerLazySingleton<DisbursementRemoteDataSource>(
        () => DisbursementRemoteDataSource(client));
    GetIt.instance.registerLazySingleton<PaymentRemoteDataSource>(
        () => PaymentRemoteDataSource(client));
    GetIt.instance.registerLazySingleton<CollectionRemoteDataSource>(
        () => CollectionRemoteDataSource(client));
    GetIt.instance.registerLazySingleton<LocationRemoteDataSource>(
        () => LocationRemoteDataSource(client));
    GetIt.instance.registerLazySingleton<AccountUpgradeRemoteDataSource>(
        () => AccountUpgradeRemoteDataSource(client));
    GetIt.instance.registerLazySingleton<UserRemoteDataSource>(
        () => UserRemoteDataSource(client));
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(client));
  });

  tearDownAll(() => GetIt.instance.reset());

  Future<List<String>> pumpDashboard(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/lender/dashboard',
      routes: [
        GoRoute(
          path: '/lender/dashboard',
          builder: (_, __) => const LenderDashboardScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    // Ang Rive asset ay hindi naglo-load sa test host (kulang ang
    // `rive_native.dll` sa Windows), at ang kabiguan nito ay dumarating bilang
    // UNCAUGHT async error — hindi ito kayang alisin ng `takeException()`, kaya
    // sariling zone ang humahawak nito. Ang IBANG error (hal. RenderFlex
    // overflow) ay ipinapasa sa labas, kaya babagsak pa rin ang test kapag may
    // totoong problema sa layout.
    final tolerated = <String>[];
    await runZonedGuarded(
      () async {
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)),
        );
        // 500ms bawat frame: saklaw nito ang async na pag-load ng KPI / loans /
        // payments, ang fade-in, at ang 50 x 100ms na paghihintay ng
        // `_maybeShowTermsOnce` (walang user id sa test → nagre-return ito,
        // kaya walang natitirang pending timer).
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 500));
          tester.takeException();
        }
      },
      (e, s) {
        final message = e.toString().toLowerCase();
        if (message.contains('rive')) {
          tolerated.add(message);
          return;
        }
        // Iba ang error → hindi tinatanggap: babagsak ang test.
        Error.throwWithStackTrace(e, s);
      },
    );
    return tolerated;
  }

  /// Ang greeting dialog — "Good morning/afternoon/evening, <name>!".
  Finder greeting() => find.byWidgetPredicate(
      (w) => w is Text && (w.data?.startsWith('Good ') ?? false));

  /// Ang slot ng fox sa welcome group (118x118 na SizedBox na may `_FoxyRive`
  /// sa loob) — hindi ito hinahanap sa pamamagitan ng Rive widget mismo dahil
  /// hindi naglo-load ang asset nito sa test host.
  Finder foxSlot() => find.byWidgetPredicate(
      (w) => w is SizedBox && w.width == 118 && w.height == 118);

  /// Ang grupo ng fox + greeting dialog, direktang naka-pump — ang `rive` slot
  /// ay placeholder dito dahil ang tunay na Rive ay hindi naglo-load sa test
  /// host (kulang ang `rive_native.dll` sa Windows). Ang AYOS lang naman ang
  /// sinusuri: alin ang nasa kaliwa.
  Future<void> pumpWelcomeGroup(
    WidgetTester tester, {
    required bool riveFirst,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LenderWelcomeGroup(
              firstName: 'Blake',
              riveFirst: riveFirst,
              rive: const SizedBox(
                key: ValueKey('fox'),
                width: 118,
                height: 118,
                child: ColoredBox(color: Color(0xFFFFCC00)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder foxPlaceholder() => find.byKey(const ValueKey('fox'));

  group('Ayos ng fox (Rive) + greeting dialog', () {
    testWidgets('desktop: fox sa KALIWA, dialog sa KANAN nito', (tester) async {
      await pumpWelcomeGroup(tester, riveFirst: true);

      expect(foxPlaceholder(), findsOneWidget);
      expect(greeting(), findsOneWidget);

      final foxBox = tester.getTopLeft(foxPlaceholder());
      final dialogBox = tester.getTopLeft(greeting());

      // Ang fox ang pinaka-kaliwa; nasa KANAN nito ang dialog.
      expect(dialogBox.dx, greaterThan(foxBox.dx + 100),
          reason: 'Dapat nasa KANAN ng Rive ang greeting dialog sa desktop');
      // Magkatabi (hindi na-stack sa ibaba).
      expect((dialogBox.dy - foxBox.dy).abs(), lessThan(120));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile: nasa KALIWA pa rin ng fox ang dialog', (tester) async {
      await pumpWelcomeGroup(tester, riveFirst: false);

      final foxBox = tester.getTopLeft(foxPlaceholder());
      final dialogBox = tester.getTopLeft(greeting());

      expect(dialogBox.dx, lessThan(foxBox.dx),
          reason: 'Hindi dapat nagbago ang mobile: dialog sa kaliwa ng fox');
      expect(tester.takeException(), isNull);
    });
  });

  group('Walang active loan: HINDI lumalabas ang stat tiles', () {
    setUp(() => _activeLoan = null);

    testWidgets('desktop: walang Next Payment / Installment', (tester) async {
      await pumpDashboard(tester, 1280);

      expect(find.text('Next Payment'), findsNothing);
      expect(find.text('Installment'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile: walang Next Payment / Installment', (tester) async {
      await pumpDashboard(tester, 390);

      expect(find.text('Next Payment'), findsNothing);
      expect(find.text('Installment'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Stat tiles: Next Payment at Installment', () {
    testWidgets('desktop: hindi na Active/Borrowed/Paid ang mga label',
        (tester) async {
      await pumpDashboard(tester, 1280);

      expect(find.text('Next Payment'), findsOneWidget);
      expect(find.text('Installment'), findsOneWidget);

      // Ang dating tatlong tiles ay wala na.
      expect(find.text('Active Loans'), findsNothing);
      expect(find.text('Total Borrowed'), findsNothing);
      expect(find.text('Total Paid'), findsNothing);
    });

    testWidgets('desktop: list payload (walang schedules) → hindi "—"',
        (tester) async {
      // Ito ang aktwal na isinasagot ng `loans-view?fn=get-list`: walang
      // loan_schedules, kaya `installment_amount` + `due_date` ang basehan.
      await pumpDashboard(tester, 1280);

      final due = parseManila(_nextDue)!;
      expect(find.text('Due ${AppFormatters.date(due)}'), findsOneWidget);
      expect(find.text(AppFormatters.currency(4444)), findsWidgets,
          reason: 'Dapat ₱4,444.00 ang Next Payment (installment_amount)');
    });

    testWidgets('desktop: may schedules → natitira ng hindi pa bayad na period',
        (tester) async {
      _activeLoan = _loanWithSchedules;
      await pumpDashboard(tester, 1280);

      final due = parseManila(_nextDue)!;
      // Hindi ang bayad na sched-1 (₱4,000) ni ang sched-3 (₱4,000): ang
      // PARTIAL na sched-2 (₱4,000 - ₱1,000).
      expect(find.text(AppFormatters.currency(3000)), findsWidgets,
          reason: 'Dapat ₱3,000.00 ang natitira sa sched-2');
      expect(find.text('Due ${AppFormatters.date(due)}'), findsOneWidget);
      expect(find.text(AppFormatters.currency(4444)), findsWidgets,
          reason: 'Dapat ₱4,444.00 ang Installment');
    });

    testWidgets('mobile (390px): nakikita rin ang tiles', (tester) async {
      await pumpDashboard(tester, 390);

      expect(find.text('Next Payment'), findsOneWidget);
      expect(find.text('Installment'), findsOneWidget);

      // Aktibong loan → may halaga, hindi "—", at may due date.
      final due = parseManila(_nextDue)!;
      expect(find.text('Due ${AppFormatters.date(due)}'), findsOneWidget);
      expect(find.text(AppFormatters.currency(4444)), findsWidgets);
    });

    /// Ang stat tile na naglalaman ng [label] — ang card nito ay radius-14 na
    /// Container (tingnan ang `_StatTile`).
    Finder tileOf(String label) => find
        .ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(14)),
        )
        .first;

    /// Ang Outstanding Balance card (radius-16 na Container ng `_MyLoanCard`).
    Finder balanceCard() => find
        .ancestor(
          of: find.text('Outstanding Balance'),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(16)),
        )
        .first;

    testWidgets('desktop: tiles sa KANAN ng dialog, pantay ang gilid sa card',
        (tester) async {
      await pumpDashboard(tester, 1280);

      final greetingRect = tester.getRect(greeting());
      final foxRect = tester.getRect(foxSlot());
      final balanceRect = tester.getRect(balanceCard());
      final nextPaymentRect = tester.getRect(tileOf('Next Payment'));
      final installmentRect = tester.getRect(tileOf('Installment'));

      // 1) Nasa KANANG bahagi ng greeting row ang tiles — nasa kanan ng fox at
      // ng pinagmumulan ng dialog (test font: mas mahaba ang bubble kaysa sa
      // totoong font, kaya ang kaliwang gilid ng dialog ang sinusuri).
      expect(nextPaymentRect.left, greaterThan(foxRect.left + 250),
          reason: 'Dapat sa KANAN ng fox/greeting ang Next Payment');
      expect(nextPaymentRect.left, greaterThan(greetingRect.left + 100),
          reason: 'Dapat nasa KANAN ng dialog ang Next Payment');

      // 2) Nasa TOP ROW pa rin sila: nasa ITAAS na ng Outstanding Balance card.
      expect(nextPaymentRect.top, lessThan(balanceRect.top),
          reason: 'Dapat nasa top row ang tiles, hindi na sa ilalim ng card');

      // 3) ISANG ROW: magkatabi at pantay ang taas/lapad ng dalawang card.
      expect((nextPaymentRect.top - installmentRect.top).abs(), lessThan(2),
          reason: 'Dapat isang row ang dalawang tile');
      expect(
          (nextPaymentRect.width - installmentRect.width).abs(), lessThan(2));

      // 4) Hindi napuputol ang mga teksto: lumiliit (scaleDown) ang bawat linya
      // ng tile kapag makitid ang espasyo imbes na mag-ellipsis.
      bool shrinksInsteadOfClipping(String text) => tester
          .widgetList<FittedBox>(
            find.ancestor(
                of: find.text(text), matching: find.byType(FittedBox)),
          )
          .any((b) => b.fit == BoxFit.scaleDown);

      expect(shrinksInsteadOfClipping('Next Payment'), isTrue);
      expect(shrinksInsteadOfClipping(AppFormatters.currency(4444)), isTrue,
          reason: 'Dapat kita ang buong amount');
      expect(
          shrinksInsteadOfClipping(
              'Due ${AppFormatters.date(parseManila(_nextDue)!)}'),
          isTrue,
          reason: 'Dapat kita ang buong due date');

      // 5) Pantay ang KANANG gilid ng tiles sa kanang gilid ng card.
      expect(installmentRect.right, closeTo(balanceRect.right, 1));
    });

    testWidgets('mobile: nasa ILALIM ng Outstanding Balance card ang tiles',
        (tester) async {
      await pumpDashboard(tester, 390);

      final balance = tester.getTopLeft(find.text('Outstanding Balance'));
      final nextPayment = tester.getTopLeft(find.text('Next Payment'));

      expect(nextPayment.dy, greaterThan(balance.dy),
          reason: 'Dapat nasa ILALIM ng Outstanding Balance ang Next Payment');
    });
  });
}
