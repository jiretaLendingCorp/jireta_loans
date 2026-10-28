// test/features/head_manager/profile/hm_profile_edit_dialog_test.dart
//
// Ang Edit Profile ng Head Manager ay dapat GANITO rin sa Edit Profile ng
// employee: Email, Gender, Civil status, at Address (hindi lang pangalan,
// phone at birthday). Ito ang verification para sa dialog at sa payload na
// ipinapadala sa `users-manage?fn=update-profile`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/profile/providers/hm_profile_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/profile/screens/hm_profile_screen.dart';
import 'package:jireta_loans/presentation/shared/widgets/philippines_address_field.dart';

import '../../../helpers/audit_test_helpers.dart';

class _FakeUserDs extends UserRemoteDataSource {
  _FakeUserDs() : super(FakeDioClient((_) async => throw UnimplementedError()));
}

class _FakeAuthDs extends AuthRemoteDataSource {
  _FakeAuthDs() : super(FakeDioClient((_) async => throw UnimplementedError()));
}

class _FakeHmProfileNotifier extends HmProfileNotifier {
  _FakeHmProfileNotifier() : super(_FakeUserDs(), _FakeAuthDs());

  UserModel? profileUser;
  Map<String, dynamic>? savedPayload;

  @override
  Future<void> loadProfile({bool silent = false}) async {
    if (profileUser != null) state = HmProfileState(user: profileUser);
  }

  @override
  Future<String?> updateProfile(Map<String, dynamic> data) async {
    savedPayload = data;
    return null;
  }
}

UserModel _hm() => UserModel(
      id: 'hm-1',
      role: 'head_manager',
      firstName: 'Mylene',
      lastName: 'Cayabyab',
      email: 'mylene@example.com',
      phoneNumber: '09343454545',
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime(2026, 1, 1),
      gender: 'female',
      civilStatus: 'married',
      dateOfBirth: DateTime(1998, 1, 22),
      streetAddress: '045 Hermosa',
      barangay: 'San Pedro',
      city: 'Dinalupihan',
      province: 'Bataan',
      zipCode: '2110',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HM ay puwedeng hindi email-format ang identifier (walang validation)',
      (tester) async {
    await loadTestEnv();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final notifier = _FakeHmProfileNotifier()..profileUser = _hm();
    final router = GoRouter(
      initialLocation: '/hm/profile',
      routes: [
        GoRoute(
          path: '/hm/profile',
          builder: (_, __) => const HmProfileScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hmProfileProvider.overrideWith((ref) => notifier),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Edit Profile').first);
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    // Head Manager: identifier lang (hindi email) dapat tanggapin at ma-save.
    final emailField = find.descendant(
      of: dialog,
      matching: find.ancestor(
        of: find.text('Email'),
        matching: find.byType(TextFormField),
      ),
    );
    expect(emailField, findsOneWidget);
    await tester.enterText(emailField, 'headmanager2');
    await tester.pump();

    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Enter a valid email address'), findsNothing);
    expect(notifier.savedPayload, isNotNull);
    expect(notifier.savedPayload!['email'], 'headmanager2');
  });

  testWidgets('HM Edit Profile has the same fields as Employee Edit Profile',
      (tester) async {
    await loadTestEnv();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final notifier = _FakeHmProfileNotifier()..profileUser = _hm();
    final router = GoRouter(
      initialLocation: '/hm/profile',
      routes: [
        GoRoute(
          path: '/hm/profile',
          builder: (_, __) => const HmProfileScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hmProfileProvider.overrideWith((ref) => notifier),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Edit Profile').first);
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    // Pareho ng employee dialog: email, gender, civil status, at address.
    expect(
        find.descendant(of: dialog, matching: find.text('Email')), findsWidgets);
    expect(find.descendant(of: dialog, matching: find.text('Gender')),
        findsWidgets);
    expect(find.descendant(of: dialog, matching: find.text('Civil status')),
        findsWidgets);
    expect(find.descendant(of: dialog, matching: find.byType(PhilippinesAddressField)),
        findsOneWidget);

    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final payload = notifier.savedPayload;
    expect(payload, isNotNull);
    expect(payload!['first_name'], 'Mylene');
    expect(payload['last_name'], 'Cayabyab');
    // Walang binagong email — hindi ito ipinapadala para hindi mag-trigger ng
    // GoTrue credential sync sa bawat save.
    expect(payload.containsKey('email'), isFalse);
    expect(payload['employee_profile'], {
      'gender': 'female',
      'civil_status': 'married',
      'date_of_birth': '1998-01-22',
    });
  });
}
