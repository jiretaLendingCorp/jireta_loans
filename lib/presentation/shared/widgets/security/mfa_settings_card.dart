// lib/presentation/shared/widgets/security/mfa_settings_card.dart
//
// Ang "Two-Factor Authentication" (Google Authenticator / TOTP) na row sa
// profile Security ng rider / lender / employee — kasama ng MPIN card:
//
//   * ipinapakita ang KASALUKUYANG status (ON / OFF / hindi matukoy);
//   * ON → Switch + "Disable 2FA" (na may reauthentication gamit ang code);
//   * OFF → Switch + enrollment dialog (QR + manual setup key + 6-digit code).
//
// Ang status ay galing sa Supabase Auth (GoTrue `mfa_factors`) — hindi ito
// itinatago sa alinmang table ng app, at walang TOTP secret na dumadaan sa
// application database o logs.
import 'package:flutter/material.dart';

import '../../../../core/security/mfa_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../profile/modern_profile_widgets.dart';
import 'mfa_dialogs.dart';

class MfaSettingsCard extends StatefulWidget {
  /// Walang card box — plain text rows lang, nakalapat sa page (rider profile).
  final bool flat;

  /// Ipakita pa rin ang icon kahit `flat` (hal. lender profile).
  final bool showIcon;

  const MfaSettingsCard(
      {super.key, this.service, this.flat = false, this.showIcon = false});

  /// Opsyonal na service (pang-test / shared instance).
  final MfaService? service;

  @override
  State<MfaSettingsCard> createState() => _MfaSettingsCardState();
}

class _MfaSettingsCardState extends State<MfaSettingsCard> {
  late final MfaService _service = widget.service ?? MfaService();

  MfaStatus? _status;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final status = await _service.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is MfaFailure ? e.message : mfaFailureFrom(e).message;
      });
    }
  }

  Future<void> _enable() async {
    if (_loading || (_status?.enrolled ?? false)) return;
    final ok = await showMfaEnrollDialog(context, service: _service);
    if (!mounted) return;
    if (ok) {
      await _load();
      if (!mounted) return;
      _toast(
        'Two-factor authentication is now on. You will be asked for a code '
        'from your authenticator app when you sign in.',
        AppColors.success,
      );
    }
  }

  Future<void> _disable() async {
    if (!(_status?.enrolled ?? false)) return;
    final ok = await showMfaDisableDialog(context, service: _service);
    if (!mounted) return;
    if (ok) {
      await _load();
      if (!mounted) return;
      _toast(
        'Two-factor authentication is now off for this account.',
        AppColors.info,
      );
    }
  }

  void _toast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  /// Mga hakbang sa recovery kapag nawala ang authenticator app. HINDI ito
  /// nagbibigay ng bypass — ang HM-assisted reset ay may identity check at
  /// naka-audit (`users-admin?fn=reset-mfa`).
  void _openRecovery() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ModernInfoSheet(
        title: '2FA recovery',
        icon: Icons.health_and_safety_outlined,
        sections: [
          ModernSheetSection(
            title: 'If you still have your authenticator app',
            body: 'Open the app and enter the current 6-digit code when asked '
                'at sign-in — nothing else is needed.',
          ),
          ModernSheetSection(
            title: 'If you lost the app or your phone',
            body: 'Contact Jireta support or your head manager. They will '
                'verify your identity (registered mobile number and account '
                'details) before resetting 2FA, and the reset is logged.',
          ),
          ModernSheetSection(
            title: 'After a reset',
            body: 'Sign in again with your registered sign-in method, then set '
                'up the authenticator app again from this screen.',
          ),
          ModernSheetSection(
            title: 'Keep your account safe',
            body: 'Never share your 6-digit codes or the setup key. Jireta '
                'staff will never ask for them.',
          ),
        ],
      ),
    );
  }

  String get _subtitle {
    if (_loading) return 'Checking…';
    if (_error != null) return 'Status unavailable — tap to retry';
    if (_status?.enrolled ?? false) {
      final name = _status!.verifiedFactors.first.friendlyName;
      return 'On · $name';
    }
    return 'Off · Add Google Authenticator as a second step';
  }

  @override
  Widget build(BuildContext context) {
    final enrolled = _status?.enrolled ?? false;
    final enabled = !_loading && _error == null;
    return ModernMenuCard(flat: widget.flat, showIcon: widget.showIcon, items: [
      ModernMenuItem(
        icon: enrolled ? Icons.verified_user_outlined : Icons.shield_outlined,
        title: 'Two-Factor Authentication',
        subtitle: _subtitle,
        onTap: !enabled ? _load : (enrolled ? _disable : _enable),
        trailing: Switch.adaptive(
          value: enrolled,
          activeTrackColor: AppColors.success,
          onChanged: !enabled
              ? null
              : (value) {
                  if (value) {
                    _enable();
                  } else {
                    _disable();
                  }
                },
        ),
      ),
      if (enrolled)
        ModernMenuItem(
          icon: Icons.health_and_safety_outlined,
          title: 'Recovery & disable 2FA',
          onTap: _openRecovery,
        ),
      if (_error != null && !_loading)
        ModernMenuItem(
          icon: Icons.refresh_rounded,
          title: 'Retry 2FA status',
          onTap: _load,
        ),
    ]);
  }
}
