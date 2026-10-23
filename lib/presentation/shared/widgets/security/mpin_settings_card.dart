// lib/presentation/shared/widgets/security/mpin_settings_card.dart
//
// Ang "MPIN" rows na lumalabas sa Profile ng rider at lender:
//   * "Set MPIN"    — unang pag-set, o pagpalit kung may naka-set na;
//   * "Reset MPIN"  — i-off ang MPIN (lumalabas lang kapag may naka-set).
//
// Ang palit at ang reset ay parehong dumadaan muna sa verification ng
// kasalukuyang MPIN kaya hindi ito mababago ng ibang tao kahit bukas ang app.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/extensions/context_extensions.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/security/mpin_service.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../profile/modern_profile_widgets.dart';
import 'mpin_dialog.dart';

class MpinSettingsCard extends ConsumerStatefulWidget {
  /// Walang card box — plain text row lang, nakalapat sa page (rider profile).
  final bool flat;

  /// Ipakita pa rin ang icon kahit `flat` (hal. lender profile).
  final bool showIcon;

  const MpinSettingsCard({super.key, this.flat = false, this.showIcon = false});

  @override
  ConsumerState<MpinSettingsCard> createState() => _MpinSettingsCardState();
}

class _MpinSettingsCardState extends ConsumerState<MpinSettingsCard> {
  final _service = MpinService();

  /// `null` habang tinitingnan pa kung may naka-set nang MPIN.
  bool? _isSet;

  /// Natitirang palit sa 15-day window (10 max).
  ({int remaining, Duration? resetIn})? _quota;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isSet = await _service.isSet();
    final quota = isSet ? await _service.changeQuota() : null;
    if (!mounted) return;
    setState(() {
      _isSet = isSet;
      _quota = quota;
    });
  }

  Future<void> _open() async {
    final wasSet = _isSet ?? false;
    // Harangin na rito kung naubos na ang 10-palit na limitasyon.
    if (wasSet && (_quota?.remaining ?? MpinService.maxChangesPerWindow) <= 0) {
      final resetIn = _quota?.resetIn;
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(
            'Limit reached: you can only change your MPIN '
            '${MpinService.maxChangesPerWindow} times within 15 days. You can '
            'change it again in ${resetIn == null ? 'a while' : _formatReset(resetIn)}.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    // Kapag may MPIN na, hihingin muna ang luma bago payagang magpalit. Ang
    // "Reset MPIN" ay nasa TAAS ng modal na ito (hindi na hiwalay na row),
    // at dumadaan pa rin sa verification ng kasalukuyang MPIN.
    var wasReset = false;
    final ok = await showMpinSetupDialog(
      context,
      requireCurrent: wasSet,
      mpin: _service,
      onReset: () => wasReset = true,
    );
    if (!mounted) return;
    if (wasReset) {
      // Hindi direktang binubura ang MPIN — kailangan muna ng OTP na may
      // purpose=reset_mpin. Reuse ang existing na Verify OTP screen.
      await _startOtpReset();
      return;
    }
    if (!ok) return;
    await _load();
    if (!mounted) return;
    context.showSnackBarAsToast(
      SnackBar(
        content: Text(
          wasSet
              ? 'Your MPIN has been updated.'
              : 'Your MPIN is now set. You will use it to confirm your '
                  'submissions.',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  /// Sinisimulan ang "Reset MPIN" flow: magpapadala ng OTP (purpose=
  /// reset_mpin) at dadalhin ang user sa Verify OTP. Doon lang makakagawa ng
  /// bagong MPIN, at ang server-issued na reset token ang magpapatunay.
  Future<void> _startOtpReset() async {
    final phone = await SecureStorage.getLoginPhone();
    if (!mounted) return;
    if (phone == null || phone.trim().isEmpty) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text(
            'We could not find your registered number. Please log in again.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final ok = await ref.read(authProvider.notifier).sendOtp(
          phone: phone,
          purpose: AppConstants.otpPurposeResetMpin,
        );
    if (!mounted) return;
    if (!ok) {
      final err = ref.read(authProvider).error;
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(
            ref.read(authProvider.notifier).extractErrorMessage(err ?? '') ??
                'Failed to send the verification code.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Opaque na token sa URL; ang numero ay nasa secure storage (hindi sa
    // address bar / browser history).
    final sessionToken = await SecureStorage.createResetOtpSession(phone);
    if (!mounted) return;
    context.go(
      Uri(
        path: RouteConstants.resetMpinOtpVerify,
        queryParameters: {'s': sessionToken},
      ).toString(),
      extra: phone,
    );
  }

  String _formatReset(Duration d) {
    if (d.inDays >= 1) {
      final days = d.inDays;
      return '$days day${days == 1 ? '' : 's'}';
    }
    if (d.inHours >= 1) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
    final mins = d.inMinutes < 1 ? 1 : d.inMinutes;
    return '$mins minute${mins == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return ModernMenuCard(flat: widget.flat, showIcon: widget.showIcon, items: [
      ModernMenuItem(
        icon: Icons.lock_outline_rounded,
        title: _isSet == true ? 'Change MPIN' : 'Set MPIN',
        onTap: _isSet == null ? () {} : _open,
      ),
    ]);
  }
}
