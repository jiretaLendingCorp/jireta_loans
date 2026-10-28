// test/terms_email_signup_fill_in_test.dart
//
// Kapag EMAIL ang ginamit sa OTP login (at sa paggawa ng lender account), ang
// email ay verified na — hindi na ito dapat hilingin muli sa "Fill In
// Information" modal. Ang modal ay dapat pangalan lang ang tanungin at, pagka-
// Continue, deretso na sa dashboard (walang Verify Your Email step).
//
// Para sa PHONE login, nananatili ang dating behavior: may Email Address field
// at may email verification pagkatapos.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jireta_loans/presentation/features/auth/screens/terms_conditions_screen.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openFillInInformation(
  WidgetTester tester, {
  required String loginIdentifier,
}) async {
  FlutterSecureStorage.setMockInitialValues({
    'login_identifier': loginIdentifier,
  });
  SharedPreferences.setMockInitialValues({});

  final authState = AuthStateNotifier()
    ..state = const AuthState(isAuthenticated: true);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => authState)],
      child: const MaterialApp(home: TermsConditionsScreen()),
    ),
  );
  await tester.pumpAndSettle();

  // Tanggapin ang dalawang checkbox, tapos buksan ang Fill In Information.
  final scrollable = find.byType(Scrollable).first;
  final checkboxes = find.byType(Checkbox);
  await tester.scrollUntilVisible(checkboxes.first, 300,
      scrollable: scrollable);
  await tester.tap(checkboxes.first);
  await tester.tap(checkboxes.last);
  await tester.pump();

  final accept = find.text('Accept & Continue');
  await tester.scrollUntilVisible(accept, 300, scrollable: scrollable);
  await tester.tap(accept);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'email login: walang Email Address field sa Fill In Information',
      (tester) async {
    await _openFillInInformation(tester,
        loginIdentifier: 'kris@example.com');

    expect(find.text('Fill In Information'), findsOneWidget);
    expect(find.text('First Name *'), findsOneWidget);
    expect(find.text('Last Name *'), findsOneWidget);
    // Verified na ang email — hindi na ito hihingin muli.
    expect(find.text('Email Address *'), findsNothing);
    expect(
      find.textContaining('Please provide your full legal name.'),
      findsOneWidget,
    );
  });

  testWidgets('phone login: nananatili ang Email Address field',
      (tester) async {
    await _openFillInInformation(tester,
        loginIdentifier: '09171234567');

    expect(find.text('Fill In Information'), findsOneWidget);
    expect(find.text('Email Address *'), findsOneWidget);
    expect(
      find.textContaining('Please provide your full legal name and email.'),
      findsOneWidget,
    );
  });
}
