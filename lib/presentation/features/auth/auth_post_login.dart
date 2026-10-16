// lib/presentation/features/auth/auth_post_login.dart
//
// Isang pinagmumulan lamang ng "susunod na screen pagkatapos mag-login" para sa
// OTP screen at sa authenticator (MFA) screen — dati ay nasa OTP screen lang
// ang lohika, at ang MFA screen ang magiging pangalawang kopya nito.
//
// Mahalaga ito para sa rider / lender: hindi sila dumederetso sa dashboard
// pagkatapos ng OTP / MFA. Ang MPIN ng account ang huling harang sa login page
// (setup kung wala pa, o "Enter MPIN" kung mayroon na).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_constants.dart';
import '../../../core/security/mpin_login_gate.dart';
import '../../../core/security/mpin_service.dart';
import '../../../core/utils/logger.dart';
import '../../shared/providers/auth_state_provider.dart';

class PostAuthDestination {
  const PostAuthDestination(this.location, {this.extra});

  final String location;
  final Object? extra;
}

/// Sinasagot kung saan dalhin ang user pagkatapos ng OTP — at, kung may
/// nakabinbing authenticator challenge, pagkatapos nito.
///
/// Kapareho ito ng dating nasa `otp_verify_screen.dart`:
///   * rider / lender na WALANG MPIN pa  → `/mpin-setup` (gagawin na ang MPIN);
///   * rider / lender na MAY MPIN na    → "locked" state + MPIN screen ng login
///                                         page (kasama ang numerong ginamit);
///   * staff na kailangang magpalit ng password → `/force-change-password`;
///   * iba pa → dashboard ng role (o login page kapag hindi kilala).
Future<PostAuthDestination> resolvePostAuthDestination(
  WidgetRef ref, {
  String? phone,
}) async {
  final state = ref.read(authStateProvider);
  final role = state.role;
  final isRiderOrLender =
      role == AppConstants.roleRider || role == AppConstants.roleLender;

  if (isRiderOrLender) {
    // TRI-STATE ang tsek dito (`true` / `false` / `null`): tanging TAHASANG
    // "wala pang MPIN" ang dumadaan sa create — kung hindi matiyak, "Enter
    // MPIN" ang lumalabas (hindi nasisira ang existing na MPIN).
    final hasMpin = await ref.read(mpinServiceProvider).statusHasMpin();
    if (mpinStepAfterOtp(hasMpin) == MpinAfterOtpStep.create) {
      return const PostAuthDestination(RouteConstants.mpinSetup);
    }
    await ref.read(authStateProvider.notifier).lockForMpinUnlock();
    return PostAuthDestination(
      RouteConstants.mobileLogin,
      extra: MpinLoginChoice(showMpin: true, phone: phone),
    );
  }

  if (state.forcePasswordChange) {
    return const PostAuthDestination(RouteConstants.forceChangePassword);
  }

  switch (role) {
    case AppConstants.roleHeadManager:
      return const PostAuthDestination(RouteConstants.hmDashboard);
    case AppConstants.roleEmployee:
      return const PostAuthDestination(RouteConstants.empDashboard);
    case AppConstants.roleRider:
      return const PostAuthDestination(RouteConstants.riderDashboard);
    case AppConstants.roleLender:
      return const PostAuthDestination(RouteConstants.lenderDashboard);
    default:
      return const PostAuthDestination(RouteConstants.mobileLogin);
  }
}

/// Binubura ang lumang MPIN (server-side) sa "Reset MPIN" na takbo. Dalawang
/// beses itong sinusubukan — kapag sumablay ang unang tawag dahil saglit na
/// nawala ang internet, hindi natutuloy ang pag-reset at mahuhulog ang user sa
/// "Enter MPIN" na hindi na niya alam ang sagot.
Future<bool> clearMpinForReset(WidgetRef ref) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      await ref.read(mpinServiceProvider).clear();
      return true;
    } catch (e) {
      AppLogger.w(
        '[MPIN] Reset bago mag-create: bigong burahin ang MPIN '
        '(try ${attempt + 1}) — $e',
      );
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }
  return false;
}
