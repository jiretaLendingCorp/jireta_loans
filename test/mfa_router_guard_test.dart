// test/mfa_router_guard_test.dart
//
// Ang MFA gate ng router (`mfaRedirect` sa `app_router.dart`).
//
// Ito ang pumipigil sa DIRECT NAVIGATION / DEEP LINK na makalampas sa
// authenticator challenge habang may nakabinbing verification. Ang tunay na
// hangganan ay server-side (`aal: aal2` + `_shared/mfa.ts`) — nasusubukan doon
// sa `supabase/functions/_shared/mfa.test.ts`. Dito ay ang UX gate.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/constants/route_constants.dart';
import 'package:jireta_loans/core/router/app_router.dart';

void main() {
  String? decide({
    bool isAuthenticated = true,
    bool mfaRequired = true,
    bool isMfaRoute = false,
    bool isPublicRoute = false,
    String? fallback,
  }) =>
      mfaRedirect(
        isAuthenticated: isAuthenticated,
        mfaRequired: mfaRequired,
        isMfaRoute: isMfaRoute,
        isPublicRoute: isPublicRoute,
        fallbackWhenNotRequired: fallback,
      );

  group('mfaRedirect — may nakabinbing challenge', () {
    test('deep link sa dashboard → /mfa-verify', () {
      expect(decide(), RouteConstants.mfaVerify);
      expect(
        decide(isMfaRoute: false),
        RouteConstants.mfaVerify,
        reason: 'Kahit /lender/dashboard o /hm/loans ang hilingin',
      );
    });

    test('mananatili sa /mfa-verify (walang redirect loop)', () {
      expect(decide(isMfaRoute: true), isNull);
    });

    test('hindi hinaharang ang mga pampublikong pahina', () {
      for (final path in [
        RouteConstants.splash,
        RouteConstants.landing,
        RouteConstants.forgotPassword,
        RouteConstants.resetPassword,
      ]) {
        expect(
          decide(isPublicRoute: true),
          isNull,
          reason: '$path ay kailangang mabuksan (recovery links)',
        );
      }
    });

    test('hindi ginalaw ang signed-out na user (login muna)', () {
      expect(decide(isAuthenticated: false), isNull);
    });
  });

  group('mfaRedirect — walang nakabinbing challenge', () {
    test('wala nang challenge pero nasa /mfa-verify → dashboard ng role', () {
      expect(
        decide(mfaRequired: false, isMfaRoute: true, fallback: '/lender/dashboard'),
        '/lender/dashboard',
      );
    });

    test('walang fallback → hindi ginagalaw', () {
      expect(decide(mfaRequired: false, isMfaRoute: true), isNull);
    });

    test('normal na pag-navigate — walang ipinag-uutos', () {
      expect(decide(mfaRequired: false), isNull);
    });
  });
}
