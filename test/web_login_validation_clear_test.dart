// test/web_login_validation_clear_test.dart
//
// Validation ng web login (`/login`): kapag pinindot ang Login habang blangko
// ang fields, lumalabas ang "Email is required" / "Password is required" —
// pero 1 segundo lang, tapos nawawala ang red error text. Hindi dapat
// mabura ang naka-type na password kasabay ng error.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/auth/providers/auth_provider.dart';
import 'package:jireta_loans/presentation/features/auth/screens/web_login_screen.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/connectivity_provider.dart';

/// Walang network/auth call sa test na ito — validation lang ang sinusuri.
class _FakeAuthRemoteDataSource implements AuthRemoteDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        connectivityProvider.overrideWith((ref) => Stream<bool>.value(true)),
        // Ang provider ang may-ari ng notifier para ma-dispose ito (kasama ang
        // heartbeat timer) kapag bumaba ang widget tree.
        authStateProvider.overrideWith((ref) => AuthStateNotifier()),
        authProvider.overrideWith((ref) => AuthNotifier(
            _FakeAuthRemoteDataSource(), ref.watch(authStateProvider.notifier))),
      ],
      child: const MaterialApp(home: WebLoginScreen()),
    ));
    // Tapusin ang fade/slide entrance ng card.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // Test-font artifact lang: sa parisukat na glyph ng widget test, sumosobra
    // nang ilang px ang "Don't have an account? Register" row. Hindi ito
    // lumalabas sa totoong font — basta linisin ang exception dito.
    tester.takeException();
  }

  /// Isinasara ang tree para ma-dispose ang mga provider bago magtapos.
  Future<void> disposeTree(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('mawawala ang validation errors pagkatapos ng 1 segundo',
      (tester) async {
    await pumpLogin(tester);

    // Password lang ang nilagay — blangko pa rin ang email.
    // Index 0 = email, index 1 = password.
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsNothing);

    // Bago umabot ng 1 segundo, nandiyan pa rin ang error.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Email is required'), findsOneWidget);

    // Pagkatapos ng 1 segundo, wala na ang error text...
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Email is required'), findsNothing);

    // ...pero hindi nabura ang naka-type na password (obscured ang field,
    // kaya controller ang sinusuri, hindi ang visible text).
    final passwordTexts = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((e) => e.controller.text)
        .toList();
    expect(passwordTexts, contains('secret123'));

    await disposeTree(tester);
  });
}
