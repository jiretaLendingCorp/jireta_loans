// lib/presentation/shared/widgets/security/email_change_otp_dialog.dart
//
// Popup na lumalabas pagkatapos humingi ng pagbabago ng email ang rider o
// lender. Dito ipinapasok ang 6-digit na code na ipinadala sa BAGONG email —
// hangga't hindi ito na-verify, hindi pa nagbabago ang email sa account
// (server ang nagtatapos ng pagbabago sa `confirm-email-change`).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// Ipinapakita ang OTP dialog para sa pagbabago ng email.
///
/// `onVerify` at `onResend` ay nagbabalik ng error message (`null` = success)
/// para hindi na kailangang humawak ng DioException ang dialog. `true` ang
/// ibinabalik kapag na-verify na ang code.
Future<bool> showEmailChangeOtpDialog(
  BuildContext context, {
  required String email,
  required Future<String?> Function(String otp) onVerify,
  required Future<String?> Function() onResend,
}) async {
  final result = await showDialog<bool>(
    context: context,
    // Sinasadya: hindi ito basta-basta isinasara ng tap sa labas — kailangan ng
    // malinaw na Cancel, at may naka-hintay na code.
    barrierDismissible: false,
    builder: (_) => _EmailChangeOtpDialog(
      email: email,
      onVerify: onVerify,
      onResend: onResend,
    ),
  );
  return result == true;
}

class _EmailChangeOtpDialog extends StatefulWidget {
  final String email;
  final Future<String?> Function(String otp) onVerify;
  final Future<String?> Function() onResend;

  const _EmailChangeOtpDialog({
    required this.email,
    required this.onVerify,
    required this.onResend,
  });

  @override
  State<_EmailChangeOtpDialog> createState() => _EmailChangeOtpDialogState();
}

class _EmailChangeOtpDialogState extends State<_EmailChangeOtpDialog> {
  /// Kapareho ng server-side cooldown (`EMAIL_CHANGE_RESEND_SECONDS`).
  static const int _resendSeconds = 60;

  final _codeCtrl = TextEditingController();
  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String get _resendLabel {
    if (_secondsLeft <= 0) return 'Resend code';
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return 'Resend code in $m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the complete 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onVerify(code);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
    _codeCtrl.clear();
  }

  Future<void> _resend() async {
    if (_busy || _secondsLeft > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onResend();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _codeCtrl.clear();
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.cSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Verify your email',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.cTextPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: context.cTextTertiary),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: context.cTextSecondary,
                  ),
                  children: [
                    const TextSpan(text: 'Enter the 6-digit code we sent to '),
                    TextSpan(
                      text: widget.email,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.cTextPrimary,
                      ),
                    ),
                    const TextSpan(
                      text: ' to finish changing your email address.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: context.cTextPrimary,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '6-digit code',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                    color: context.cTextTertiary,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.cBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.cBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: context.cBrandGreen, width: 1.6),
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _verify(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: (_busy || _secondsLeft > 0) ? null : _resend,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _resendLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: (_busy || _secondsLeft > 0)
                          ? context.cTextTertiary
                          : context.cBrandGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.cTextSecondary,
                          side: BorderSide(color: context.cBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: _busy ? null : _verify,
                        style: FilledButton.styleFrom(
                          backgroundColor: context.cBrandGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Verify',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
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
