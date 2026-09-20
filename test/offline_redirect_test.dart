// test/offline_redirect_test.dart
//
// Regression tests para sa "laging lumalabas ang splash sa mobile" bug.
//
// Ang splash ay maaaring puntahan sa dalawang paraan lang:
//   1. `initialLocation` (pagbukas ng app), at
//   2. ang OFFLINE branch ng redirect sa `app_router.dart`.
//
// Dati, ang (2) ay nagpapabalik sa MOBILE na user sa `/splash` kapag
// `connVal == false` — kahit nasa MPIN o Verify OTP screen na siya. Dahil ang
// reachability probe ay bawat 5 segundo (4s timeout) at nagiging sticky ang
// `false` hanggang sa susunod na matagumpay na probe, ang anumang
// `router.refresh()` sa bintanang iyon (hal. ang OTP → MPIN at MPIN → login na
// paglipat) ay bumubulaga sa splash.
//
// Ang splash ay LAUNCH screen lamang: kapag nakaalis na ang user dito, hindi na
// ito ibinabalik ng redirect.
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/constants/route_constants.dart';
import 'package:jireta_loans/core/router/app_router.dart';

void main() {
  group('offlineRedirect — mobile', () {
    test('hindi ibinabalik sa splash ang nakaalis na (unauthenticated)', () {
      // Ito ang mga screen kung saan aktwal na nakikita ang bug: MPIN at
      // Verify OTP — parehong hindi authenticated sa sandaling iyon.
      expect(
        offlineRedirect(
          isWeb: false,
          path: RouteConstants.mobileLogin,
          authenticatedTarget: null,
        ),
        isNull,
      );
      expect(
        offlineRedirect(
          isWeb: false,
          path: RouteConstants.otpVerify,
          authenticatedTarget: null,
        ),
        isNull,
      );
      expect(
        offlineRedirect(
          isWeb: false,
          path: RouteConstants.mpinSetup,
          authenticatedTarget: null,
        ),
        isNull,
      );
    });

    test('nananatili sa splash kapag naroon pa (launch)', () {
      expect(
        offlineRedirect(
          isWeb: false,
          path: RouteConstants.splash,
          authenticatedTarget: null,
        ),
        isNull,
      );
    });

    test('ang naka-authenticate ay hindi ginagalaw mula sa screen ng role', () {
      // Ang target ay ibinibigay ng caller (redirectForRole) — hindi ito
      // binabago ng offline branch, kaya nananatili ang dating ugali.
      expect(
        offlineRedirect(
          isWeb: false,
          path: '/lender/dashboard',
          authenticatedTarget: RouteConstants.lenderDashboard,
        ),
        RouteConstants.lenderDashboard,
      );
      // Nasa one-time setup / public route → walang target → hindi gagalawin
      // (hal. hindi itutulak sa dashboard habang nasa MPIN setup).
      expect(
        offlineRedirect(
          isWeb: false,
          path: RouteConstants.mpinSetup,
          authenticatedTarget: null,
        ),
        isNull,
      );
    });
  });

  group('offlineRedirect — web', () {
    test('nananatili sa splash ang web app habang offline', () {
      expect(
        offlineRedirect(
          isWeb: true,
          path: RouteConstants.webLogin,
          authenticatedTarget: null,
        ),
        RouteConstants.splash,
      );
      expect(
        offlineRedirect(
          isWeb: true,
          path: RouteConstants.lenderDashboard,
          authenticatedTarget: RouteConstants.lenderDashboard,
        ),
        RouteConstants.splash,
      );
    });

    test('hindi na inuulit ang pag-navigate kapag nasa splash na', () {
      expect(
        offlineRedirect(
          isWeb: true,
          path: RouteConstants.splash,
          authenticatedTarget: null,
        ),
        isNull,
      );
    });
  });
}
