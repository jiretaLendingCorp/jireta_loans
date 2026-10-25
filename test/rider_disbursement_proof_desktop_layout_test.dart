// test/rider_disbursement_proof_desktop_layout_test.dart
//
// CASH ON DELIVERY PROOF — DESKTOP LAYOUT
//
//   * Desktop: DALAWANG column — Cash on Delivery photos sa kaliwa, Lender
//     Signature sa kanan — naka-cap (1080) at nakasentro, at naka-align sa
//     kanan ang Submit + Cancel (380). Dati, isang column lang na nakaunat sa
//     buong lapad.
//   * Mobile: isang column pa rin (hindi binago).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/disbursement_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/location_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/presentation/shared/widgets/app_button.dart';
import 'package:jireta_loans/presentation/features/rider/disbursements/screens/rider_disbursement_upload_proof_screen.dart';
import 'package:jireta_loans/presentation/features/rider/location/providers/rider_location_provider.dart';

import 'helpers/audit_test_helpers.dart';

FakeDioClient _offlineClient() => FakeDioClient((o) async => Response<dynamic>(
      requestOptions: o,
      data: {
        'data': <dynamic>[],
        'meta': {'unread_count': 0, 'total': 0},
      },
    ));

/// Walang GPS sa widget test — huwag galawin ang geolocator.
class _StubLocationNotifier extends RiderLocationNotifier {
  _StubLocationNotifier()
      : super(LocationRemoteDataSource(_offlineClient()));

  @override
  void startTracking() {}

  @override
  void stopTracking() {}
}

void main() {
  setUpAll(() async {
    await loadTestEnv();
  });

  setUp(() {
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(_offlineClient()));
    GetIt.instance.registerLazySingleton<DisbursementRemoteDataSource>(
        () => DisbursementRemoteDataSource(_offlineClient()));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpScreen(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/rider/disbursements/d1/proof',
      routes: [
        GoRoute(
          path: '/rider/disbursements/:id/proof',
          builder: (_, state) => RiderDisbursementUploadProofScreen(
              disbursementId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        riderLocationProvider.overrideWith((ref) => _StubLocationNotifier()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('desktop: dalawang column, naka-cap ang lapad, right-aligned actions',
      (tester) async {
    await pumpScreen(tester, 1400);

    expect(tester.takeException(), isNull);
    expect(find.text('Lender Signature (Optional)'), findsOneWidget);
    expect(find.text('No photo yet'), findsOneWidget);

    // Magkatabi: nasa KANAN ang signature card, lampas sa Upload button ng
    // photo card (na nasa ilalim ng kaliwang column).
    final upload = tester.getRect(find.text('Upload'));
    final signature = tester.getRect(find.text('Lender Signature (Optional)'));
    expect(signature.left, greaterThan(upload.right));
    expect(signature.top, lessThan(upload.top));

    // Naka-cap (1080) ang content — hindi nakaunat sa buong desktop body.
    final cap = find
        .byWidgetPredicate(
            (w) => w is ConstrainedBox && w.constraints.maxWidth == 1080)
        .first;
    final capRect = tester.getRect(cap);
    expect(capRect.width, lessThanOrEqualTo(1080));
    expect(capRect.width, greaterThan(600));

    // Ang "Tap Upload … (max 5MB each)" na helper text ay nasa LOOB ng photo
    // card — sa kaliwang bahagi ng Clear/Upload row.
    final hint = find.textContaining('max 5MB total');
    expect(hint, findsOneWidget);
    final photoCardRect =
        tester.getRect(find.byKey(const ValueKey('cod_photo_card')));
    expect(photoCardRect.contains(tester.getRect(hint).center), isTrue);
    // Ang "Clear" sa photo card — may sariling Clear din ang signature pad.
    final photoClear = find.descendant(
        of: find.byKey(const ValueKey('cod_photo_card')),
        matching: find.text('Clear'));
    expect(tester.getRect(hint).left, lessThan(tester.getRect(photoClear).left));

    // MAGKAPANTAY ang taas ng dalawang card.
    final photoCard = tester.getRect(find.byKey(const ValueKey('cod_photo_card')));
    final signatureCard =
        tester.getRect(find.byKey(const ValueKey('cod_signature_card')));
    expect(photoCard.height, closeTo(signatureCard.height, 1),
        reason: 'Hindi pantay ang taas ng photo at signature cards');

    // Submit lang sa desktop — walang Cancel.
    expect(find.text('Cancel'), findsNothing);
    // Ang AppButton (hindi ang text sa loob nito) ang sinusukat: 380 ang cap
    // at nakadikit sa kanang gilid ng content.
    final submit = tester.getRect(find.byType(AppButton));
    expect(submit.width, closeTo(380, 1));
    expect(capRect.right - submit.right, lessThan(40));
  });

  testWidgets('mobile: isang column pa rin', (tester) async {
    await pumpScreen(tester, 390);

    expect(tester.takeException(), isNull);
    final upload = tester.getRect(find.text('Upload'));
    final signature = tester.getRect(find.text('Lender Signature (Optional)'));
    expect(signature.top, greaterThan(upload.bottom));

    // Sa mobile, nandiyan pa rin ang Cancel.
    expect(find.text('Cancel'), findsOneWidget);
  });
}
