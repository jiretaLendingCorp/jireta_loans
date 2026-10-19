// test/force_change_password_validation_test.dart
//
// Ang validation messages sa /force-change-password ay dating nananatili
// kahit blangko pa rin ang fields (o pagkatapos i-submit). Ngayon, 2 segundo
// pagkatapos ng failed submit, kusang nawawala ang mga error — pero HINDI
// binubura ang naka-type na password.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/auth/providers/auth_provider.dart';
import 'package:jireta_loans/presentation/features/auth/screens/force_change_password_screen.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';

/// Walang network/auth call sa test na ito — validation lang ang sinusuri.
/// `noSuchMethod` ang sumasagot sa mga method ng datasource.
class _FakeAuthRemoteDataSource implements AuthRemoteDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Ang provider ang may-ari ng notifier para ma-dispose ito (kasama ang
        // 60s heartbeat timer) kapag bumaba ang widget tree.
        authStateProvider.overrideWith((ref) => AuthStateNotifier()),
        authProvider.overrideWith((ref) => AuthNotifier(
            _FakeAuthRemoteDataSource(), ref.watch(authStateProvider.notifier))),
      ],
      child: const MaterialApp(home: ForceChangePasswordScreen()),
    ));
    await tester.pump();
  }

  testWidgets('validation errors auto-clear after 2 seconds', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Update Password'));
    await tester.pump();

    // Ang hint at error ay parehong text sa current/confirm fields, kaya
    // dalawa ang mahanap habang naka-show ang validation error.
    expect(find.text('Enter your current password'), findsNWidgets(2));
    expect(find.text('Enter a new password'), findsOneWidget);
    expect(find.text('Re-enter your new password'), findsNWidgets(2));

    // Wala pang 2 segundo — nandiyan pa ang mga error.
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('Enter a new password'), findsOneWidget,
        reason: 'Nawala agad bago pa umabot ng 2 segundo');

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // Pagkalipas ng 2 segundo — disposed/cleared na ang validation errors;
    // ang hint text lang ang natitira sa current/confirm fields.
    expect(find.text('Enter your current password'), findsOneWidget);
    expect(find.text('Enter a new password'), findsNothing);
    expect(find.text('Re-enter your new password'), findsOneWidget);

    // Isara ang tree para ma-dispose ang AuthStateNotifier timer.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
