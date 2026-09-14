// lib/core/security/submission_guard.dart
//
// Isang lugar lang ang flow ng "kumpirmahin bago mag-submit":
//
//   1. Device credential (fingerprint / Face ID / device PIN/password) —
//      kapag may naka-set na password ang phone, ito ang una.
//   2. Kapag WALANG device password (unavailable / unsupported), ang app-level
//      4-digit MPIN ang gagamitin.
//   3. Kapag wala pang naka-set na MPIN, HIHINGIN MUNA itong i-set bago
//      payagang mag-submit.
//
// Ginagamit ito ng lahat ng submission ng rider at lender — loan application,
// bayad, collection record, CI report, disbursement proof, atbp. — kaya
// isang behavior lang ang sinusundan ng lahat.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/shared/widgets/security/mpin_dialog.dart';
import '../extensions/context_extensions.dart';
import '../theme/app_colors.dart';
import 'device_auth_service.dart';
import 'mpin_service.dart';

/// Paliwanag na ipinapakita sa MPIN setup kapag kailangan munang mag-set ng
/// MPIN bago makapag-submit (walang device password ang phone).
const String kMpinRequiredBeforeSubmitMessage =
    'Walang password o biometrics ang phone mo, kaya kailangan mo munang '
    'mag-set ng 4-digit MPIN. Ito ang gagamitin para kumpirmahin ang mga '
    'submission mo. Puwede rin itong palitan anumang oras sa Profile.';

/// Kumpirmasyon bago ang isang submission.
class SubmissionGuard {
  const SubmissionGuard({
    required DeviceAuthService deviceAuth,
    required MpinService mpin,
  })  : _deviceAuth = deviceAuth,
        _mpin = mpin;

  final DeviceAuthService _deviceAuth;
  final MpinService _mpin;

  /// Humihingi ng verification bago ang isang submission.
  ///
  /// Nagbabalik ng `true` kapag na-verify (ituloy ang submission) at `false`
  /// kapag kinansela / mali / kulang ang setup (hindi dapat ituloy).
  Future<bool> confirm(
    BuildContext context, {
    required String reason,
  }) async {
    final outcome = await _deviceAuth.authenticate(reason: reason);

    switch (outcome) {
      case DeviceAuthOutcome.success:
        return true;

      case DeviceAuthOutcome.failed:
        if (context.mounted) {
          context.showSnackBarAsToast(
            const SnackBar(
              content: Text(kDeviceAuthFailedMessage),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return false;

      case DeviceAuthOutcome.unavailable:
      case DeviceAuthOutcome.unsupported:
        // Walang device password/biometric sa phone na ito — MPIN ang
        // fallback (ito ang dahilan kung bakit may MPIN ang app).
        break;
    }

    if (!context.mounted) return false;

    if (await _mpin.isSet()) {
      if (!context.mounted) return false;
      return showMpinVerifyDialog(context, reason: reason, mpin: _mpin);
    }

    // Wala pang MPIN — required muna itong i-set bago makapag-proceed.
    if (!context.mounted) return false;
    final setup = await showMpinSetupDialog(
      context,
      reason: kMpinRequiredBeforeSubmitMessage,
      mpin: _mpin,
    );
    if (setup) return true;

    if (context.mounted) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text(
            'Kailangan ng MPIN bago mag-submit. Mag-set ng 4-digit MPIN sa '
            'Profile o sa susunod na submit.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
    }
    return false;
  }
}

final submissionGuardProvider = Provider<SubmissionGuard>(
  (ref) => SubmissionGuard(
    deviceAuth: ref.read(deviceAuthServiceProvider),
    mpin: ref.read(mpinServiceProvider),
  ),
);
