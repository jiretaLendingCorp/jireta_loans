// lib/presentation/shared/widgets/security/reset_mfa_dialog.dart
//
// Ang "Reset 2FA" action na ginagamit ng Head Manager sa lender at rider
// (list rows at details) kapag nawala ng user ang authenticator app.
//
// Ang tunay na hangganan ay server-side (`users-admin?fn=reset-mfa`):
// HEAD MANAGER lang, hindi maaaring i-reset ang sariling account, naka-audit
// (`mfa_reset`), at may rate limit. Dito ang UI lang — confirm, spinner habang
// tumatawag, at toast pagkatapos.
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/datasources/remote/user_remote_datasource.dart';
import '../dialogs/confirmation_dialog.dart';

/// Hihingin ang confirmation, tapos i-reset ang 2FA ng [userId].
///
/// [roleLabel] ay "lender" o "rider" (para sa dialog copy), at [personName]
/// ang buong pangalan ng target.
Future<void> confirmAndResetMfa(
  BuildContext context, {
  required String userId,
  required String personName,
  required String roleLabel,
}) async {
  var removed = 0;
  final done = await showAsyncConfirmationDialog(
    context,
    title: 'Reset 2FA?',
    message: 'This removes the authenticator app of '
        '$personName ($roleLabel). Do this only after verifying their '
        'identity. They can then sign in with the mobile number and SMS OTP, '
        'and set up 2FA again afterwards. The reset is logged in the audit '
        'trail.',
    confirmLabel: 'Reset 2FA',
    confirmColor: AppColors.error,
    icon: Icons.security_outlined,
    onConfirm: () async {
      try {
        removed = await sl<UserRemoteDataSource>().resetMfa(userId);
        return null;
      } catch (e) {
        return ErrorHandler.handle(e).message;
      }
    },
  );
  if (done != true || !context.mounted) return;
  if (removed > 0) {
    context.showSuccessToast(
      '2FA reset. $personName can sign in with SMS OTP and set up 2FA again.',
    );
  } else {
    context.showToast('This account has no authenticator app set up.');
  }
}
