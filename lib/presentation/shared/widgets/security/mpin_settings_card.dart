// lib/presentation/shared/widgets/security/mpin_settings_card.dart
//
// Ang "MPIN" rows na lumalabas sa Profile ng rider at lender:
//   * "Set MPIN"    — unang pag-set, o pagpalit kung may naka-set na;
//   * "Reset MPIN"  — i-off ang MPIN (lumalabas lang kapag may naka-set).
//
// Ang palit at ang reset ay parehong dumadaan muna sa verification ng
// kasalukuyang MPIN kaya hindi ito mababago ng ibang tao kahit bukas ang app.
import 'package:flutter/material.dart';

import 'package:jireta_loans/core/extensions/context_extensions.dart';

import '../../../../core/security/mpin_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../profile/modern_profile_widgets.dart';
import 'mpin_dialog.dart';

class MpinSettingsCard extends StatefulWidget {
  const MpinSettingsCard({super.key});

  @override
  State<MpinSettingsCard> createState() => _MpinSettingsCardState();
}

class _MpinSettingsCardState extends State<MpinSettingsCard> {
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
    // Kapag may MPIN na, hihingin muna ang luma bago payagang magpalit.
    final ok = await showMpinSetupDialog(
      context,
      requireCurrent: wasSet,
      mpin: _service,
    );
    if (!mounted || !ok) return;
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

  /// Nagpapa-verify muna ng kasalukuyang MPIN bago ito i-off. Kapag nakalimutan
  /// na ito, hindi rito ma-reset — kailangan ng tulong ng support.
  Future<void> _reset() async {
    if (_isSet != true) return;
    // Kapag naubos na ang palit sa 15-day window, walang MPIN na maiiwan ang
    // user matapos mag-reset at hindi siya makakapag-set ng bago — sabihan na
    // siya bago pa ito mangyari.
    final blocked = (_quota?.remaining ?? MpinService.maxChangesPerWindow) <= 0;
    final resetIn = _quota?.resetIn;
    final verified = await showMpinVerifyDialog(
      context,
      reason: blocked
          ? 'Enter your current MPIN to reset it. Note: you have used all '
              '${MpinService.maxChangesPerWindow} changes for now, so you '
              'cannot set a new MPIN until ${resetIn == null ? 'later' : 'in ${_formatReset(resetIn)}'}.'
          : 'Enter your current MPIN to reset it. Your MPIN will be turned '
              'off and you can set a new one anytime.',
      mpin: _service,
    );
    if (!mounted || !verified) return;
    await _service.clear();
    await _load();
    if (!mounted) return;
    context.showSnackBarAsToast(
      const SnackBar(
        content: Text(
          'Your MPIN has been reset. Set a new one anytime from this screen.',
        ),
        backgroundColor: AppColors.info,
      ),
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
    return ModernMenuCard(items: [
      ModernMenuItem(
        icon: Icons.lock_outline_rounded,
        title: _isSet == true ? 'Change MPIN' : 'Set MPIN',
        onTap: _isSet == null ? () {} : _open,
      ),
      // Kapag wala pang MPIN, walang mabe-reset — itago na lang ang row.
      if (_isSet == true)
        ModernMenuItem(
          icon: Icons.lock_reset_rounded,
          title: 'Reset MPIN',
          onTap: _reset,
        ),
    ]);
  }
}
