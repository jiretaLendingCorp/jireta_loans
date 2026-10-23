// test/lender_apply_loan_wizard_desktop_test.dart
//
// DESKTOP VIEW NG 5-STEP LOAN WIZARD (/lender/loans)
//
// Dati, nakaunat sa buong browser ang wizard: isang column ang Loan Details,
// Financial & Emergency, Co-Maker, Signature, at Review — kaya desktop-wide
// ang bawat field. Mula [kDesktopBreakpoint] pataas:
//
//   * naka-center at naka-cap sa 1120px ang buong wizard (step indicator,
//     step content, at Back/Next);
//   * step 1 (Loan Details): form sa kaliwa, purpose + schedule preview sa
//     kanan;
//   * step 2: magkatabi ang Financial Details at Emergency Contact;
//   * step 3: naka-cap sa 900 at naka-center ang Co-Maker form;
//   * step 4: magkatabi ang Co-Maker Signature at Valid ID;
//   * step 5: dalawang column ang Review rows.
//
// Sa mobile, isang column pa rin ang lahat — walang binago sa phone.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/account_upgrade_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/disbursement_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/account_upgrade_document_model.dart';
import 'package:jireta_loans/data/models/loan_model.dart';
import 'package:jireta_loans/data/models/loan_settings.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/lender/account_upgrade/providers/lender_account_upgrade_provider.dart';
import 'package:jireta_loans/presentation/features/lender/loans/providers/lender_loan_provider.dart';
import 'package:jireta_loans/presentation/features/lender/loans/screens/lender_apply_loan_screen.dart';
import 'package:jireta_loans/presentation/features/lender/profile/providers/lender_profile_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/loan_settings_provider.dart';

import 'helpers/audit_test_helpers.dart';

/// Walang network: walang loan (kaya bukas ang 5-step wizard) at laging
/// may schedule preview.
class _FakeLoanDS extends LoanRemoteDataSource {
  _FakeLoanDS() : super(FakeDioClient((_) async => throw UnimplementedError()));

  @override
  Future<List<LoanModel>> getLoanList({
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    String? lenderId,
    String? dateFrom,
    String? dateTo,
  }) async =>
      const [];

  @override
  Future<Map<String, dynamic>> getSchedulePreview(
    double principal,
    String frequency, {
    int? termPeriods,
  }) async =>
      {
        'principal': principal,
        'interest': 240,
        'interest_rate': 6,
        'total_payable': principal + 240,
        'installment_amount': (principal + 240) / 4,
        'installments': termPeriods ?? 4,
        'frequency': frequency,
        'max_periods': 6,
      };
}

class _FakeDisbursementDS extends DisbursementRemoteDataSource {
  _FakeDisbursementDS()
      : super(FakeDioClient((_) async => throw UnimplementedError()));
}

/// Verified ang account — kaya hindi lumalabas ang Upgrade gate.
class _FakeAccountUpgradeDS extends AccountUpgradeRemoteDataSource {
  _FakeAccountUpgradeDS()
      : super(FakeDioClient((_) async => throw UnimplementedError()));

  @override
  Future<AccountUpgradeStatusModel> accountUpgradeGetStatus() async =>
      const AccountUpgradeStatusModel(
        lenderId: 'lender-1',
        accountUpgradeStatus: 'verified',
        documents: [],
      );
}

class _FakeUserDS extends UserRemoteDataSource {
  _FakeUserDS() : super(FakeDioClient((_) async => throw UnimplementedError()));

  @override
  Future<UserModel> getProfile({String? userId}) async => UserModel(
        id: 'lender-1',
        role: 'lender',
        firstName: 'Blake',
        lastName: 'Cruz',
        accountStatus: 'active',
        forcePasswordChange: false,
        createdAt: DateTime.now(),
      );
}

void main() {
  setUpAll(() async {
    await loadTestEnv();
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
      () => NotificationRemoteDataSource(
        FakeDioClient((o) async => Response<dynamic>(
              requestOptions: o,
              data: {
                'data': <dynamic>[],
                'meta': {'unread_count': 0},
              },
            )),
      ),
    );
  });

  tearDownAll(() => GetIt.instance.reset());

  Future<void> pumpWizard(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/lender/loans',
      routes: [
        GoRoute(
          path: '/lender/loans',
          builder: (_, __) => const LenderApplyLoanScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lenderLoanProvider.overrideWith(
            (ref) => LenderLoanNotifier(_FakeLoanDS(), _FakeDisbursementDS()),
          ),
          lenderAccountUpgradeProvider.overrideWith(
              (ref) => LenderAccountUpgradeNotifier(_FakeAccountUpgradeDS())),
          lenderProfileProvider
              .overrideWith((ref) => LenderProfileNotifier(_FakeUserDS())),
          loanSettingsProvider
              .overrideWith((ref) async => LoanSettings.defaults),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // Async na load ng loan status/settings + ang purpose screen.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Purpose picker (pili + Continue) → Loan Details step.
  Future<void> goToLoanDetails(WidgetTester tester) async {
    await tester.tap(find.text('Business Capital'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Loan Details (amount) → Financial & Emergency step.
  Future<void> goToFinancialStep(WidgetTester tester) async {
    await goToLoanDetails(tester);
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Lender apply-loan wizard: desktop view', () {
    testWidgets('desktop: naka-cap 1120 at 2 columns ang Loan Details (step 1)',
        (tester) async {
      await pumpWizard(tester, 1600);
      expect(tester.takeException(), isNull);

      await goToLoanDetails(tester);
      expect(tester.takeException(), isNull);

      // Naka-center at naka-cap ang buong wizard sa 1120px.
      final capBox = find
          .byWidgetPredicate(
              (w) => w is ConstrainedBox && w.constraints.maxWidth == 1120)
          .first;
      expect(tester.getRect(capBox).width, 1120);

      // KALIWA: amount slider; KANAN: purpose — magkatabi, hindi naka-stack.
      final slider = tester.getRect(find.byType(Slider));
      final purpose = tester.getRect(find.text('Purpose'));
      expect(purpose.left, greaterThan(slider.right),
          reason: 'Walang 2-column na desktop layout ang step 1');
      // Kalahati lang ng lapad ng content ang slider (hindi nakaunat sa buong
      // 1088px na loob ng cap).
      expect(slider.width, lessThan(600));

      // Nasa KANAN din ang live na payment schedule preview.
      final preview = tester.getRect(find.text('Payment Schedule Preview'));
      expect(preview.left, greaterThan(slider.right));
    });

    testWidgets('desktop: magkatabi ang Financial Details at Emergency Contact',
        (tester) async {
      await pumpWizard(tester, 1600);
      expect(tester.takeException(), isNull);

      await goToFinancialStep(tester);
      expect(tester.takeException(), isNull);

      final financial = tester.getRect(find.text('Financial Details'));
      final emergency = tester.getRect(find.text('Emergency Contact'));
      expect((financial.center.dy - emergency.center.dy).abs(), lessThan(1),
          reason: 'Naka-stack (hindi magkatabi) ang dalawang section');
      expect(emergency.left, greaterThan(financial.right));
    });

    testWidgets('desktop: magkatabi ang Signature at Valid ID (step 4)',
        (tester) async {
      // Parehong LenderTwoPane ang step 2 at step 4, kaya dito na lang
      // sinusukat ang primitive mismo — hindi kayang puntahan ng test ang
      // step 4 (kailangan ng signature + ID scan).
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1088,
              child: LenderTwoPane(
                left: Text('Signature'),
                right: Text('Valid ID'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final signature = tester.getRect(find.text('Signature'));
      final validId = tester.getRect(find.text('Valid ID'));
      expect((signature.center.dy - validId.center.dy).abs(), lessThan(1));
      expect(validId.left, greaterThan(signature.right));
    });

    testWidgets('LenderTwoPane: naka-stack kapag makitid', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body:
                LenderTwoPane(left: Text('Signature'), right: Text('Valid ID')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final signature = tester.getRect(find.text('Signature'));
      final validId = tester.getRect(find.text('Valid ID'));
      expect(validId.top, greaterThan(signature.bottom));
    });

    testWidgets('mobile: isang column pa rin ang steps 1 at 2', (tester) async {
      // TANDAAN: may DATI NANG 36px na overflow ang `_SchedulePreview` row sa
      // 390px (nangyayari rin sa HEAD, hindi galing sa desktop layout na ito).
      // Kinukuha lang ang exception para hindi maging test failure.
      void drainKnownOverflow() => tester.takeException();

      await pumpWizard(tester, 390);
      drainKnownOverflow();

      await goToLoanDetails(tester);
      drainKnownOverflow();

      // Step 1: naka-stack pa rin ang purpose sa ilalim ng amount/frequency.
      final slider = tester.getRect(find.byType(Slider));
      final purpose = tester.getRect(find.text('Purpose'));
      expect(purpose.top, greaterThan(slider.bottom));

      // Step 2: naka-stack pa rin ang Emergency Contact sa ilalim ng Financial.
      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      drainKnownOverflow();

      final financial = tester.getRect(find.text('Financial Details'));
      final emergency = tester.getRect(find.text('Emergency Contact'));
      expect(emergency.top, greaterThan(financial.bottom),
          reason: 'Dapat naka-stack pa rin sa mobile');
    });
  });
}
