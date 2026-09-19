// lib/presentation/features/auth/screens/reset_password_screen.dart
// OTP-based password reset per spec:
// Forgot Password -> Email -> OTP (6-digit) -> Verify -> New Password -> Supabase Auth update
// Styling mirrors the web login / register / forgot-password screens.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import '../widgets/password_strength_indicator.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _currentCtrl = TextEditingController();
  final _currentFocus = FocusNode();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _done = false;
  bool _otpVerified = false;
  bool _verifying = false;
  String? _otpError;
  int _secondsLeft = 0;
  Timer? _resendTimer;
  int _lockSecondsLeft = 0;
  Timer? _lockTimer;
  bool _otpExpired = false;
  bool _resending = false;

  /// Server-side rejection of the submitted current password (field-level).
  String? _currentPasswordError;

  /// Opaque reset-flow token from the URL (`?t=<64 hex chars>`).
  ///
  /// SECURITY: this replaces the account email in the URL. The email used to
  /// travel as `?email=...`, which leaks the account identifier into browser
  /// history, server/proxy access logs, analytics and the Referer header of
  /// third-party requests. The token is a random, non-reversible handle the
  /// server maps back to the email internally.
  String? _resetToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      String? token;
      try {
        token = GoRouterState.of(context).uri.queryParameters['t'];
      } catch (_) {}
      token ??= Uri.base.queryParameters['t'];
      // The email is handed over in memory (GoRouterState.extra) — never in the
      // URL. It is only used for display and for resending; a reload loses it
      // and the token above keeps the flow working.
      String? handoffEmail;
      try {
        final extra = GoRouterState.of(context).extra;
        if (extra is String && extra.isNotEmpty) handoffEmail = extra;
      } catch (_) {}
      if (token != null && token.isNotEmpty) _resetToken = token;
      if (handoffEmail != null) _emailCtrl.text = handoffEmail;
      if (mounted && (_resetToken != null || handoffEmail != null)) {
        setState(() {});
      }
      _startResendTimer();
    });
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _secondsLeft = 60;
      _otpExpired = false;
      // Clear stale expired message when a fresh OTP is issued
      if (_otpError ==
          'OTP expired. Please tap Resend Code to get a new one.') {
        _otpError = null;
      }
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        if (mounted) {
          setState(() {
            _secondsLeft = 0;
            if (!_otpVerified) {
              _otpExpired = true;
              _otpError =
                  'OTP expired. Please tap Resend Code to get a new one.';
              for (final c in _otpControllers) {
                c.clear();
              }
            }
          });
        }
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  void _startLockCountdown(int seconds) {
    _lockTimer?.cancel();
    setState(() => _lockSecondsLeft = seconds);
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_lockSecondsLeft <= 1) {
        t.cancel();
        if (mounted) setState(() => _lockSecondsLeft = 0);
      } else {
        if (mounted) setState(() => _lockSecondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _currentCtrl.dispose();
    _currentFocus.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocus) {
      f.dispose();
    }
    _resendTimer?.cancel();
    _lockTimer?.cancel();
    super.dispose();
  }

  String get _otp => _otpControllers.map((c) => c.text).join();

  void _onOtpChanged(int index, String value) {
    if (_otpError != null) setState(() => _otpError = null);
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < digits.length && (index + i) < 6; i++) {
        _otpControllers[index + i].text = digits[i];
      }
      final next = (index + digits.length).clamp(0, 5);
      _otpFocus[next].requestFocus();
    } else if (value.isNotEmpty) {
      if (index < 5) _otpFocus[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpFocus[index - 1].requestFocus();
    }
    if (_otp.length == 6) {
      // Auto-verify when 6 digits entered and not yet verified
      if (!_otpVerified &&
          !_otpExpired &&
          _secondsLeft > 0 &&
          _lockSecondsLeft == 0) {
        _verifyOtp();
      }
    }
  }

  Future<void> _verifyOtp() async {
    final email = _emailCtrl.text.trim();
    final otp = _otp;
    final token = _resetToken;
    final hasToken = token != null && token.isNotEmpty;
    if (email.isEmpty && !hasToken) {
      setState(() => _otpError =
          'Reset session expired. Go back to Forgot Password and request a new code.');
      return;
    }
    if (email.isNotEmpty && !AppValidators.isValidEmail(email)) {
      setState(() => _otpError = 'Invalid email format.');
      return;
    }
    if (otp.length != 6) {
      setState(() => _otpError = 'Enter 6-digit code');
      return;
    }
    if (_lockSecondsLeft > 0) return;
    if (_otpExpired) {
      setState(() =>
          _otpError = 'OTP expired. Please tap Resend Code to get a new one.');
      return;
    }
    if (_secondsLeft == 0 && !_otpVerified) {
      setState(() {
        _otpExpired = true;
        _otpError = 'OTP expired. Please tap Resend Code to get a new one.';
      });
      return;
    }
    setState(() {
      _verifying = true;
      _otpError = null;
    });
    // Token first: with it the email is not sent at all — the server resolves
    // the account from the opaque handle.
    final ok = await ref.read(authProvider.notifier).verifyResetOtp(
          otp: otp,
          email: hasToken ? null : email,
          resetToken: token,
        );
    if (!mounted) return;
    setState(() => _verifying = false);
    if (ok) {
      _resendTimer?.cancel();
      setState(() {
        _otpVerified = true;
        // A fresh verification invalidates any stale field error from before.
        _currentPasswordError = null;
      });
      context.showSnackBarAsToast(
        const SnackBar(
            content: Text('OTP verified. Set your new password.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating),
      );
    } else {
      final err = ref.read(authProvider).error;
      final msg =
          ref.read(authProvider.notifier).extractErrorMessage(err ?? '') ??
              'Invalid or expired OTP';
      final lockSecs =
          ref.read(authProvider.notifier).extractOtpLockoutSeconds(err ?? '');
      if (lockSecs != null && lockSecs > 0) {
        _startLockCountdown(lockSecs);
        setState(() => _otpError = msg);
      } else {
        setState(() => _otpError = msg);
      }
      // Clear OTP for retry
      for (final c in _otpControllers) {
        c.clear();
      }
      _otpFocus[0].requestFocus();
    }
  }

  Future<void> _resendOtp() async {
    if (_lockSecondsLeft > 0 || _resending) return;
    // Resending mints a brand-new code, so it needs the email (the server
    // cannot address the mail from the token alone). The token from the URL is
    // not enough here — ask for the address only when it is unknown.
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      context.showSnackBarAsToast(const SnackBar(
          content: Text('Enter the email you used above to resend the code.'),
          backgroundColor: AppColors.error));
      return;
    }
    if (!AppValidators.isValidEmail(email)) {
      context.showSnackBarAsToast(const SnackBar(
          content: Text('Invalid email format.'),
          backgroundColor: AppColors.error));
      return;
    }
    setState(() => _resending = true);
    final ok =
        await ref.read(authProvider.notifier).forgotPassword(email: email);
    if (!mounted) return;
    setState(() => _resending = false);
    if (ok) {
      // Every send rotates the flow token (the previous row is invalidated
      // server-side), so keep the newest one for verify/reset. The URL is left
      // untouched on purpose — rewriting it would rebuild this screen and wipe
      // the in-progress state.
      final rotated = ref.read(authProvider.notifier).resetToken;
      _startResendTimer();
      for (final c in _otpControllers) {
        c.clear();
      }
      setState(() {
        if (rotated != null && rotated.isNotEmpty) _resetToken = rotated;
        _otpError = null;
        _otpVerified = false;
      });
      _otpFocus[0].requestFocus();
      context.showSnackBarAsToast(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.mark_email_read_rounded,
                  color: Colors.black, size: 20),
              SizedBox(width: 10),
              Expanded(
                  child: Text('Code resent — check your inbox.',
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w600))),
            ],
          ),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              side: BorderSide(color: Colors.black, width: 1.4)),
          elevation: 8,
        ),
      );
    } else {
      final err = ref.read(authProvider).error;
      final msg =
          ref.read(authProvider.notifier).extractErrorMessage(err ?? '') ??
              'Failed to resend code';
      final lockSecs =
          ref.read(authProvider.notifier).extractOtpLockoutSeconds(err ?? '');
      if (lockSecs != null && lockSecs > 0) _startLockCountdown(lockSecs);
      context.showSnackBarAsToast(SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
    }
  }

  Future<void> _submitNewPassword() async {
    if (!_otpVerified) {
      context.showSnackBarAsToast(const SnackBar(
          content: Text('Please verify OTP first'),
          backgroundColor: AppColors.error));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final otp = _otp;
    // Defensive: OTP should still be present from Step 1 (hidden after verified).
    // If empty, force re-verify.
    if (otp.isEmpty || otp.length != 6) {
      setState(() {
        _otpVerified = false;
        _otpExpired = true;
        _otpError = 'OTP expired. Please tap Resend Code to get a new one.';
      });
      _resendTimer?.cancel();
      setState(() => _secondsLeft = 0);
      for (final c in _otpControllers) {
        c.clear();
      }
      context.showSnackBarAsToast(const SnackBar(
          content: Text('OTP expired. Please resend and verify again.'),
          backgroundColor: AppColors.error));
      return;
    }
    final newPassword = _newCtrl.text;
    final notifier = ref.read(authProvider.notifier);
    final token = _resetToken;
    final hasToken = token != null && token.isNotEmpty;
    final ok = await notifier.resetPassword(
      otp: otp,
      newPassword: newPassword,
      email: hasToken ? null : email,
      resetToken: token,
      currentPassword: _currentCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      _resendTimer?.cancel();
      setState(() => _done = true);
      _currentCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
      for (final c in _otpControllers) {
        c.clear();
      }
    } else {
      final err = ref.read(authProvider).error;
      final msg = notifier.extractErrorMessage(err ?? '') ??
          'Failed to reset password. Check OTP or try again.';
      // Wrong current password → inline field error, stay on this step. Must be
      // handled before the OTP check below, whose 'invalid' match would
      // otherwise bounce the user back to re-entering the code.
      if (notifier.isCurrentPasswordError(err)) {
        final lockSecs = notifier.extractOtpLockoutSeconds(err ?? '');
        if (lockSecs != null && lockSecs > 0) _startLockCountdown(lockSecs);
        setState(() => _currentPasswordError = msg);
        _formKey.currentState?.validate();
        _currentFocus.requestFocus();
        return;
      }
      // Too many wrong attempts → the server locked this email for a while.
      final lockSecs = notifier.extractOtpLockoutSeconds(err ?? '');
      if (lockSecs != null && lockSecs > 0) _startLockCountdown(lockSecs);
      // If backend says OTP invalid/expired even though we were verified, the
      // window likely elapsed before reset (extended to 10 min after verify).
      // Treat as session expired and bounce back to Step 1.
      final isOtpError = msg.toLowerCase().contains('otp') ||
          msg.toLowerCase().contains('expired') ||
          msg.toLowerCase().contains('invalid');
      if (isOtpError) {
        setState(() {
          _otpVerified = false;
          _otpExpired = true;
          _otpError = msg;
        });
        _resendTimer?.cancel();
        setState(() => _secondsLeft = 0);
        for (final c in _otpControllers) {
          c.clear();
        }
        _otpFocus[0].requestFocus();
      }
      context.showSnackBarAsToast(SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared input styling — mirrors the login / forgot-password forms
  // ───────────────────────────────────────────────────────────────────────────

  InputDecoration _input({String? hint, IconData? icon, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          fontSize: 13.5,
          color: AppColors.textTertiary.withValues(alpha: 0.75)),
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 18, color: AppColors.textTertiary),
      suffixIcon: suffix,
      counterText: '',
      errorMaxLines: 3,
      errorStyle:
          const TextStyle(fontSize: 12, height: 1.35, color: AppColors.error),
      filled: true,
      fillColor: const Color(0xFFF8F9FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE4E7EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.deepNavy, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.4),
      ),
    );
  }

  static const _inputStyle = TextStyle(
      fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500);

  Widget _passwordToggle(bool obscure, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 18,
          color: AppColors.textSecondary),
      onPressed: onPressed,
      tooltip: obscure ? 'Show password' : 'Hide password',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: _ResetPanel(
        onBack: () {
          if (_otpVerified && !_done) {
            // Keep the user on the card but step back to verification.
            setState(() => _otpVerified = false);
            return;
          }
          context.go(RouteConstants.webLogin);
        },
        child: _done ? _buildSuccess() : _buildContent(isLoading),
      ),
    );
  }

  Widget _buildContent(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Text(
            _otpVerified ? 'Set New Password' : 'Reset Password',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: AppColors.deepNavy,
              height: 1.1,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _otpVerified
                ? 'Create a new password for your account.'
                : 'Enter the 6-digit code sent to your email.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: AppColors.textSecondary.withValues(alpha: 0.9),
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 28),
        if (!_otpVerified) _buildOtpStep() else _buildPasswordStep(isLoading),
      ],
    );
  }

  // ── Step 1: OTP only (email already provided from Forgot Password) ──

  Widget _buildOtpStep() {
    final expired = _otpExpired || _secondsLeft == 0;
    final email = _emailCtrl.text.trim();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (email.isNotEmpty)
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mail_outlined,
                      size: 16, color: AppColors.textTertiary),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'Code sent to $email',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Reached after a page reload: the URL token still authorises the
            // verify/reset calls, so the email is only needed to resend.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.info, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _resetToken == null
                          ? 'Reset session expired. Go back to Forgot Password to request a new code.'
                          : 'Code sent to your email. Enter the address below only if you need to resend it.',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColors.info.withValues(alpha: 0.95)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _FieldLabel('Email Address'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              maxLength: 254,
              style: _inputStyle,
              decoration:
                  _input(hint: 'you@example.com', icon: Icons.mail_outlined),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 22),
          Center(
            child: SizedBox(
              width: 360,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _buildOtpBox(i)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Single status line: error wins, then lock, then live countdown.
          if (_otpError != null)
            Center(
              child: Text(
                _otpError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: AppColors.error),
              ),
            )
          else
            Center(
              child: Text(
                _lockSecondsLeft > 0
                    ? 'Locked for $_lockSecondsLeft seconds'
                    : expired
                        ? 'Code expired — resend to continue.'
                        : 'Code expires in $_secondsLeft seconds',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          if (_lockSecondsLeft > 0) ...[
            const SizedBox(height: 16),
            _LockBanner(secondsLeft: _lockSecondsLeft),
          ],
          const SizedBox(height: 22),
          _PrimaryButton(
            label: 'Verify',
            loading: _verifying,
            onPressed: (_verifying ||
                    _lockSecondsLeft > 0 ||
                    _otp.length != 6 ||
                    _otpExpired ||
                    _secondsLeft == 0)
                ? null
                : _verifyOtp,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed:
                  (_lockSecondsLeft == 0 && !_resending) ? _resendOtp : null,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                foregroundColor: AppColors.deepNavy,
                shape: const RoundedRectangleBorder(),
              ),
              child: _resending
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.deepNavy)),
                        SizedBox(width: 8),
                        Text('Sending...',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    )
                  : Text(
                      _lockSecondsLeft > 0 ? 'Resend locked' : 'Resend code',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    final invalid = _otpError != null ||
        _otpExpired ||
        (_secondsLeft == 0 && !_otpVerified);
    final locked = _lockSecondsLeft > 0;
    final verified = _otpVerified;
    final expired = invalid && !verified;
    return SizedBox(
      width: 46,
      height: 54,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_otpControllers[index].text.isEmpty && index > 0) {
              _otpControllers[index - 1].clear();
              _otpFocus[index - 1].requestFocus();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: TextFormField(
          controller: _otpControllers[index],
          focusNode: _otpFocus[index],
          readOnly: locked || verified || expired,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: verified
                  ? AppColors.success
                  : expired
                      ? AppColors.error
                      : AppColors.deepNavy),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: verified
                ? AppColors.successLight
                : expired
                    ? AppColors.errorLight
                    : const Color(0xFFF8F9FC),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: verified
                    ? AppColors.success
                    : expired
                        ? AppColors.error
                        : const Color(0xFFE4E7EE),
                width: expired || verified ? 1.4 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: verified
                    ? AppColors.success
                    : expired
                        ? AppColors.error
                        : AppColors.deepNavy,
                width: 1.6,
              ),
            ),
          ),
          onChanged: (v) => _onOtpChanged(index, v),
          onTap: () {
            _otpControllers[index].selection = TextSelection.fromPosition(
                TextPosition(offset: _otpControllers[index].text.length));
          },
        ),
      ),
    );
  }

  // ── Step 2: password form (shown only after OTP verified) ──

  Widget _buildPasswordStep(bool isLoading) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Plain centered status line — deliberately not a bordered/filled
          // chip so it never reads as a tappable button.
          const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded,
                    size: 16, color: AppColors.success),
                SizedBox(width: 7),
                Text(
                  'OTP verified — set your new password',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _FieldLabel('Current Password'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _currentCtrl,
            focusNode: _currentFocus,
            obscureText: _obscureCurrent,
            maxLength: 128,
            textInputAction: TextInputAction.next,
            style: _inputStyle,
            onChanged: (_) {
              // Clear the server's rejection as soon as the user retypes.
              if (_currentPasswordError != null) {
                setState(() => _currentPasswordError = null);
              }
            },
            decoration: _input(
              hint: 'Enter current password',
              icon: Icons.lock_outline_rounded,
              suffix: _passwordToggle(_obscureCurrent,
                  () => setState(() => _obscureCurrent = !_obscureCurrent)),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Current password is required';
              if (v.length < 8) return 'Password must be at least 8 characters';
              return _currentPasswordError;
            },
          ),
          const SizedBox(height: 18),
          const _FieldLabel('New Password'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _newCtrl,
            obscureText: _obscureNew,
            maxLength: 64,
            textInputAction: TextInputAction.next,
            style: _inputStyle,
            onChanged: (_) {
              setState(() {});
              if (_confirmCtrl.text.isNotEmpty) {
                _formKey.currentState?.validate();
              }
            },
            decoration: _input(
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              suffix: _passwordToggle(_obscureNew,
                  () => setState(() => _obscureNew = !_obscureNew)),
            ),
            validator: (v) {
              final basic = AppValidators.password(v);
              if (basic != null) return basic;
              if (_currentCtrl.text.isNotEmpty && v == _currentCtrl.text) {
                return 'New password must differ from current';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          PasswordStrengthIndicator(password: _newCtrl.text),
          const SizedBox(height: 18),
          const _FieldLabel('Confirm New Password'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            maxLength: 64,
            textInputAction: TextInputAction.done,
            style: _inputStyle,
            decoration: _input(
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              suffix: _passwordToggle(_obscureConfirm,
                  () => setState(() => _obscureConfirm = !_obscureConfirm)),
            ),
            validator: (v) => AppValidators.confirmPassword(v, _newCtrl.text),
            onFieldSubmitted: (_) => _submitNewPassword(),
          ),
          const SizedBox(height: 26),
          _PrimaryButton(
            label: 'Change Password',
            loading: isLoading,
            onPressed: (isLoading || _lockSecondsLeft > 0)
                ? null
                : () {
                    if (_currentPasswordError != null) {
                      setState(() => _currentPasswordError = null);
                    }
                    _submitNewPassword();
                  },
          ),
          if (_lockSecondsLeft > 0) ...[
            const SizedBox(height: 16),
            _LockBanner(secondsLeft: _lockSecondsLeft),
          ],
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _otpVerified = false),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                foregroundColor: AppColors.deepNavy,
                shape: const RoundedRectangleBorder(),
              ),
              child: const Text('Back to verification',
                  style:
                      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: success ──

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFBF6EA),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
          ),
          child: const Icon(Icons.check_rounded,
              size: 28, color: AppColors.deepNavy),
        ),
        const SizedBox(height: 18),
        const Text(
          'Password Reset!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.deepNavy,
            height: 1.15,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your password has been updated successfully. Please log in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.5, height: 1.6, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 26),
        _PrimaryButton(
          label: 'Back to Login',
          onPressed: () => context.go(RouteConstants.webLogin),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel — light gradient surface hosting the centered form
// ─────────────────────────────────────────────────────────────────────────────

class _ResetPanel extends StatelessWidget {
  final Widget child;
  final VoidCallback onBack;
  const _ResetPanel({required this.child, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCFCFE), Color(0xFFF6F7FB)],
        ),
      ),
      child: Stack(
        children: [
          // faint gold glow echoing the login / register / forgot panels
          Positioned(
            top: -120,
            right: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.gold.withValues(alpha: 0.06),
                  AppColors.gold.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(
                      side: BorderSide(color: Color(0xFFE4E7EE))),
                  child: IconButton(
                    onPressed: onBack,
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back,
                        size: 20, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Builder(builder: (context) {
              final narrow = MediaQuery.sizeOf(context).width < 600;
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: narrow ? 16 : 32,
                  vertical: narrow ? 28 : 72,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: child,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared pieces (lifted from the login / register screens)
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary),
    );
  }
}

class _LockBanner extends StatelessWidget {
  final int secondsLeft;
  const _LockBanner({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
                color: AppColors.error, shape: BoxShape.circle),
            child:
                const Icon(Icons.timer_rounded, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Too many attempts',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error),
            ),
          ),
          Text(
            '$secondsLeft s',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.error,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null || widget.loading;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && !isDisabled ? 1.01 : 1.0,
        duration: const Duration(milliseconds: 140),
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: isDisabled
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0D1B2A),
                      Color(0xFF1E3A5F),
                      Color(0xFF0D1B2A),
                    ],
                  ),
            color:
                isDisabled ? AppColors.deepNavy.withValues(alpha: 0.42) : null,
            boxShadow: isDisabled
                ? []
                : [
                    BoxShadow(
                        color: AppColors.deepNavy.withValues(alpha: 0.16),
                        blurRadius: 12,
                        offset: const Offset(0, 6))
                  ],
          ),
          child: ElevatedButton(
            onPressed: isDisabled ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.transparent,
              disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
              shadowColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1),
            ),
            child: widget.loading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(widget.label),
          ),
        ),
      ),
    );
  }
}
