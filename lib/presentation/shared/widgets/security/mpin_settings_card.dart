// lib/presentation/shared/widgets/security/mpin_settings_card.dart
//
// Ang "MPIN" row na lumalabas sa Profile ng rider at lender. Isang tap lang
// para mag-set (o magpalit) ng 4-digit MPIN. Ang palitan ay dumadaan muna sa
// verification ng lumang MPIN kaya hindi ito mababago ng ibang tao kahit
// bukas ang app.
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
            'Naabot na ang limitasyon: ${MpinService.maxChangesPerWindow} '
            'palit lang ng MPIN sa loob ng 15 araw. Puwede kang magpalit muli '
            'sa ${resetIn == null ? 'lalong madaling panahon' : _formatReset(resetIn)}.',
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
              ? 'Na-update ang MPIN mo.'
              : 'Naka-set na ang MPIN mo. Ito ang gagamitin para kumpirmahin '
                  'ang mga submission mo.',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  String get _subtitle {
    switch (_isSet) {
      case null:
        return 'Checking…';
      case true:
        final remaining = _quota?.remaining ?? MpinService.maxChangesPerWindow;
        return 'On — 4-digit MPIN is set · $remaining change${remaining == 1 ? '' : 's'} left (15 days)';
      default:
        return 'Off — mag-set ng 4-digit MPIN para sa submissions';
    }
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
        subtitle: _subtitle,
        onTap: _isSet == null ? () {} : _open,
      ),
    ]);
  }
}
