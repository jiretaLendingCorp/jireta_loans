// lib/presentation/shared/widgets/security/mfa_dialogs.dart
//
// Ang dalawang dialog ng authenticator (TOTP) 2FA:
//
//   * [showMfaEnrollDialog]  — QR code + manual setup key + 6-digit na
//     pagpapatunay. Ang factor ay nananatiling `unverified` sa GoTrue hangga't
//     hindi tumama ang code, kaya hindi ito kailanman nagiging second factor
//     dahil lang sa pagkansela (at inaalis pa ito ng dialog sa pagkansela).
//   * [showMfaDisableDialog] — reauthentication (kasalukuyang code) BAGO
//     maalis ang factor; hindi ipinagpapalit ang MPIN/password dito.
//
// Ang TOTP secret ay nananatili sa GoTrue — ang QR at ang manual key ay
// ipinapakita LANG sa user sa dialog na ito (hindi ito isinusulat sa logs,
// analytics, URL, o database ng app).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/security/mfa_service.dart';
import '../../../../core/theme/app_colors.dart';

/// Nagsisimula ng TOTP enrollment at nagbabalik ng `true` kapag na-verify
/// (2FA ON). `false` kapag kinansela (at nalinis ang hindi pa na-verify na
/// factor).
Future<bool> showMfaEnrollDialog(
  BuildContext context, {
  MfaService? service,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MfaEnrollDialog(service: service),
  );
  return result == true;
}

/// Hihingin ang kasalukuyang 6-digit code bago i-off ang 2FA. `true` kapag
/// tuluyang naalis ang factor.
Future<bool> showMfaDisableDialog(
  BuildContext context, {
  MfaService? service,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MfaDisableDialog(service: service),
  );
  return result == true;
}

class MfaEnrollDialog extends StatefulWidget {
  const MfaEnrollDialog({super.key, this.service});

  /// Opsyonal na service (pang-test / shared instance).
  final MfaService? service;

  @override
  State<MfaEnrollDialog> createState() => _MfaEnrollDialogState();
}

class _MfaEnrollDialogState extends State<MfaEnrollDialog> {
  late final MfaService _service = widget.service ?? MfaService();
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  MfaEnrollment? _enrollment;
  bool _preparing = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final enrollment = await _service.beginEnrollment();
      if (!mounted) return;
      setState(() {
        _enrollment = enrollment;
        _preparing = false;
      });
      _codeFocus.requestFocus();
    } on MfaFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = mfaFailureFrom(e).message;
      });
    }
  }

  Future<void> _confirm() async {
    final code = _codeCtrl.text.trim();
    if (_busy || _enrollment == null) return;
    if (!MfaService.isValidCode(code)) {
      setState(() => _error = 'Enter the 6-digit code from the authenticator '
          'app.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.confirmEnrollment(code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on MfaFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      _codeCtrl.clear();
      _codeFocus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = mfaFailureFrom(e).message;
      });
      _codeCtrl.clear();
      _codeFocus.requestFocus();
    }
  }

  /// Kinansela ng user: inaalis ang hindi pa na-verify na factor para hindi
  /// maiwan ang kalat na entry sa authenticator app / GoTrue.
  Future<void> _cancel() async {
    if (_busy) return;
    await _service.cancelEnrollment();
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _copyKey() async {
    final key = _enrollment?.manualKey ?? '';
    if (key.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: key));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Setup key copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Harangin ang back button / swipe: dapat dumaan sa `_cancel` para malinis
    // ang unverified factor.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_cancel());
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, Icons.phonelink_lock_outlined,
                    'Set up two-factor authentication'),
                const SizedBox(height: 10),
                Text(
                  'Scan the QR code with Google Authenticator (or any '
                  'authenticator app), then enter the 6-digit code it shows.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: context.cTextSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                if (_preparing)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_enrollment == null)
                  _retryBox(context)
                else ...[
                  _qrBox(context, _enrollment!),
                  const SizedBox(height: 14),
                  _manualKeyBox(context, _enrollment!),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _codeCtrl,
                    focusNode: _codeFocus,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontSize: 22,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      hintStyle:
                          const TextStyle(fontSize: 20, letterSpacing: 8),
                      filled: true,
                      fillColor: context.cSurfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _confirm(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _errorRow(_error!),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _cancel,
                      style: TextButton.styleFrom(
                        foregroundColor: context.cTextSecondary,
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    if (_busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      FilledButton(
                        onPressed: _enrollment == null ? null : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.deepNavy,
                        ),
                        child: const Text('Verify & enable'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _qrBox(BuildContext context, MfaEnrollment enrollment) {
    final svg = enrollment.qrSvg;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(
        children: [
          if (svg != null)
            SvgPicture.string(
              svg,
              width: 190,
              height: 190,
              placeholderBuilder: (_) => const SizedBox(
                width: 190,
                height: 190,
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'The QR code could not be displayed. Use the setup key below '
                'instead.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: context.cTextSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _manualKeyBox(BuildContext context, MfaEnrollment enrollment) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Or enter this setup key manually',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.cTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: context.cSurfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.cBorder),
                ),
                child: SelectableText(
                  enrollment.manualKey,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontFamily: 'monospace',
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy setup key',
              onPressed: _copyKey,
              icon: const Icon(Icons.copy_all_outlined, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  Widget _retryBox(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _errorRow(_error ??
            'We could not start the setup. Please check your internet '
                'connection.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

class MfaDisableDialog extends StatefulWidget {
  const MfaDisableDialog({super.key, this.service});

  final MfaService? service;

  @override
  State<MfaDisableDialog> createState() => _MfaDisableDialogState();
}

class _MfaDisableDialogState extends State<MfaDisableDialog> {
  late final MfaService _service = widget.service ?? MfaService();
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _disable() async {
    final code = _codeCtrl.text.trim();
    if (_busy) return;
    if (!MfaService.isValidCode(code)) {
      setState(() => _error = 'Enter the 6-digit code from the authenticator '
          'app.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.disable(code: code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on MfaFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      _codeCtrl.clear();
      _codeFocus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = mfaFailureFrom(e).message;
      });
      _codeCtrl.clear();
      _codeFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, Icons.gpp_maybe_outlined, 'Disable 2FA'),
              const SizedBox(height: 10),
              Text(
                'Enter the current 6-digit code from your authenticator app to '
                'confirm. This keeps your account protected from anyone who '
                'only has your phone and OTP.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: context.cTextSecondary,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _codeCtrl,
                focusNode: _codeFocus,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 22,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  hintStyle: const TextStyle(fontSize: 20, letterSpacing: 8),
                  filled: true,
                  fillColor: context.cSurfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _disable(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _errorRow(_error!),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: context.cTextSecondary,
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  if (_busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    FilledButton(
                      onPressed: _disable,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                      ),
                      child: const Text('Disable 2FA'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _header(BuildContext context, IconData icon, String title) {
  return Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.deepNavy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: AppColors.deepNavy),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.cTextPrimary,
          ),
        ),
      ),
    ],
  );
}

Widget _errorRow(String message) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          message,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: AppColors.error,
          ),
        ),
      ),
    ],
  );
}
