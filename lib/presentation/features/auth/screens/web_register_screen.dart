// lib/presentation/features/auth/screens/web_register_screen.dart
// OTP-gated registration: form -> send OTP via Resend -> enter 6-digit code -> create account
// Mirrors forgot-password OTP flow.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class WebRegisterScreen extends ConsumerStatefulWidget {
  const WebRegisterScreen({super.key});

  @override
  ConsumerState<WebRegisterScreen> createState() => _WebRegisterScreenState();
}

class _WebRegisterScreenState extends ConsumerState<WebRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _submitted = false;

  // OTP step state
  bool _otpStep = false;
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());
  bool _sendingOtp = false;
  bool _verifying = false;
  bool _resending = false;
  String? _otpError;
  int _secondsLeft = 0;
  Timer? _resendTimer;
  int _lockSecondsLeft = 0;
  Timer? _lockTimer;
  bool _otpExpired = false;

  // Field-level duplication errors from 409
  String? _emailDuplicationError;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
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

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _secondsLeft = 60;
      _otpExpired = false;
      if (_otpError == 'OTP expired. Please tap Resend Code to get a new one.') {
        _otpError = null;
      }
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        if (mounted) {
          setState(() {
            _secondsLeft = 0;
            _otpExpired = true;
            _otpError = 'OTP expired. Please tap Resend Code to get a new one.';
            for (final c in _otpControllers) {
              c.clear();
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
      if (!_otpExpired && _secondsLeft > 0 && _lockSecondsLeft == 0 && !_verifying) {
        _verifyAndRegister();
      }
    }
  }

  Future<void> _sendOtp() async {
    setState(() {
      _emailDuplicationError = null;
      _otpError = null;
    });
    if (!_formKey.currentState!.validate()) return;

    final email = AppValidators.normalizeEmail(_emailCtrl.text);
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();

    setState(() => _sendingOtp = true);
    final repoError = await ref.read(authProvider.notifier).sendRegisterOtp(
          email: email,
          firstName: firstName,
          lastName: lastName,
        );
    if (!mounted) return;
    setState(() => _sendingOtp = false);

    if (repoError == null) {
      setState(() {
        _otpStep = true;
        _otpError = null;
        _otpExpired = false;
      });
      for (final c in _otpControllers) {
        c.clear();
      }
      _startResendTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFocus[0].requestFocus();
      });
      context.showSnackBarAsToast(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.mark_email_read_rounded, color: Colors.black, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Verification code sent — check your inbox.', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600))),
            ],
          ),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)), side: BorderSide(color: Colors.black, width: 1.4)),
          elevation: 8,
        ),
      );
    } else {
      final isEmailDup = AppValidators.isEmailDuplicateError(repoError);
      if (isEmailDup) {
        setState(() => _emailDuplicationError = AppValidators.duplicateEmailMessage);
        _formKey.currentState!.validate();
      }
      // Rate limit / OTP lockout hint
      final lockSecs = ref.read(authProvider.notifier).extractOtpLockoutSeconds(repoError);
      if (lockSecs != null && lockSecs > 0) _startLockCountdown(lockSecs);

      // Duplicate email is already shown inline under the field — no toast.
      if (!isEmailDup) {
        context.showSnackBarAsToast(
          SnackBar(
            content: Text(repoError),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_lockSecondsLeft > 0 || _resending) return;
    final email = AppValidators.normalizeEmail(_emailCtrl.text);
    if (email.isEmpty) {
      context.showSnackBarAsToast(const SnackBar(content: Text('No email found.'), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _resending = true);
    final repoError = await ref.read(authProvider.notifier).sendRegisterOtp(email: email, firstName: _firstNameCtrl.text.trim(), lastName: _lastNameCtrl.text.trim());
    if (!mounted) return;
    setState(() => _resending = false);
    if (repoError == null) {
      _startResendTimer();
      for (final c in _otpControllers) {
        c.clear();
      }
      setState(() => _otpError = null);
      _otpFocus[0].requestFocus();
      context.showSnackBarAsToast(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.mark_email_read_rounded, color: Colors.black, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Code resent — check your inbox.', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600))),
            ],
          ),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)), side: BorderSide(color: Colors.black, width: 1.4)),
          elevation: 8,
        ),
      );
    } else {
      final lockSecs = ref.read(authProvider.notifier).extractOtpLockoutSeconds(repoError);
      if (lockSecs != null && lockSecs > 0) _startLockCountdown(lockSecs);
      context.showSnackBarAsToast(SnackBar(content: Text(repoError), backgroundColor: AppColors.error));
    }
  }

  Future<void> _verifyAndRegister() async {
    final otp = _otp;
    if (otp.length != 6) {
      setState(() => _otpError = 'Enter 6-digit code');
      return;
    }
    if (_lockSecondsLeft > 0) return;
    if (_otpExpired) {
      setState(() => _otpError = 'OTP expired. Please tap Resend Code to get a new one.');
      return;
    }
    if (_secondsLeft == 0) {
      setState(() {
        _otpExpired = true;
        _otpError = 'OTP expired. Please tap Resend Code to get a new one.';
      });
      return;
    }
    // Re-validate form (password etc) before creating account
    if (!_formKey.currentState!.validate()) {
      setState(() => _otpStep = false);
      context.showSnackBarAsToast(const SnackBar(content: Text('Please correct the form details first.'), backgroundColor: AppColors.error));
      return;
    }

    setState(() {
      _verifying = true;
      _otpError = null;
    });

    final repoError = await ref.read(authProvider.notifier).register(
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          email: AppValidators.normalizeEmail(_emailCtrl.text),
          password: _passwordCtrl.text,
          otp: otp,
        );

    if (!mounted) return;
    setState(() => _verifying = false);

    if (repoError == null) {
      _resendTimer?.cancel();
      _lockTimer?.cancel();
      setState(() {
        _submitted = true;
        _otpStep = false;
      });
    } else {
      final isEmailDup = AppValidators.isEmailDuplicateError(repoError);
      if (isEmailDup) {
        setState(() => _emailDuplicationError = AppValidators.duplicateEmailMessage);
        setState(() => _otpStep = false);
        _formKey.currentState!.validate();
      }
      final lockSecs = ref.read(authProvider.notifier).extractOtpLockoutSeconds(repoError);
      if (lockSecs != null && lockSecs > 0) {
        _startLockCountdown(lockSecs);
      }
      final isOtpError = repoError.toLowerCase().contains('otp') || repoError.toLowerCase().contains('expired') || repoError.toLowerCase().contains('invalid');
      if (isOtpError) {
        setState(() => _otpError = repoError);
        for (final c in _otpControllers) {
          c.clear();
        }
        _otpFocus[0].requestFocus();
        // If OTP expired, mark expired so resend is required
        if (repoError.toLowerCase().contains('expired')) {
          setState(() {
            _otpExpired = true;
            _secondsLeft = 0;
          });
          _resendTimer?.cancel();
        }
      }
      // Duplicate email is already shown inline under the field — no toast.
      if (!isEmailDup) {
        context.showSnackBarAsToast(
          SnackBar(
            content: Text(repoError),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared input styling — mirrors the web login card
  // ───────────────────────────────────────────────────────────────────────────

  InputDecoration _input({String? hint, IconData? icon, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          fontSize: 13.5, color: AppColors.textTertiary.withValues(alpha: 0.75)),
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 18, color: AppColors.textTertiary),
      suffixIcon: suffix,
      counterText: '',
      // Server-side messages (e.g. duplicate email) are long — let them wrap
      // instead of being clipped to a single ellipsised line.
      errorMaxLines: 3,
      errorStyle: const TextStyle(
          fontSize: 12, height: 1.35, color: AppColors.error),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: _RegisterPanel(
        onBack: () {
          if (_otpStep) {
            _resendTimer?.cancel();
            setState(() {
              _otpStep = false;
              _otpError = null;
            });
          } else {
            context.go(RouteConstants.webLogin);
          }
        },
        child: _submitted
            ? _buildSuccess()
            : (_otpStep ? _buildOtpStep() : _buildForm()),
      ),
    );
  }

  // ── Step 1: details ──

  Widget _buildForm() {
    final isLoading = _sendingOtp;
    return _AuthCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Center(
              child: Text(
                'Create your account',
                textAlign: TextAlign.center,
                style: TextStyle(
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
                'Fill in your details, then verify your email to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.6,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w400),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FieldLabel('First Name'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _firstNameCtrl,
                        maxLength: 50,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-']")),
                          LengthLimitingTextInputFormatter(50),
                        ],
                        style: _inputStyle,
                        decoration:
                            _input(hint: 'Juan', icon: Icons.person_outlined),
                        validator: (v) => AppValidators.required(v, 'First name'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FieldLabel('Last Name'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _lastNameCtrl,
                        maxLength: 50,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-']")),
                          LengthLimitingTextInputFormatter(50),
                        ],
                        style: _inputStyle,
                        decoration: _input(hint: 'Dela Cruz'),
                        validator: (v) => AppValidators.required(v, 'Last name'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _FieldLabel('Email Address'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              maxLength: 254,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              inputFormatters: [LengthLimitingTextInputFormatter(254)],
              style: _inputStyle,
              onChanged: (_) {
                if (_emailDuplicationError != null) setState(() => _emailDuplicationError = null);
              },
              decoration: _input(
                  hint: 'you@example.com', icon: Icons.mail_outlined),
              validator: (v) {
                if (_emailDuplicationError != null) return _emailDuplicationError;
                if (v == null || v.isEmpty) return 'Email is required';
                if (!AppValidators.isValidEmail(v)) return 'Enter a valid email address';
                return null;
              },
            ),
            const SizedBox(height: 18),
            const _FieldLabel('Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              maxLength: 64,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(64)],
              style: _inputStyle,
              decoration: _input(
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: AppColors.textSecondary),
                  onPressed: () => setState(() => _obscure = !_obscure),
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                ),
              ),
              validator: AppValidators.password,
            ),
            const SizedBox(height: 18),
            const _FieldLabel('Confirm Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmPasswordCtrl,
              obscureText: _obscureConfirm,
              maxLength: 64,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(64)],
              style: _inputStyle,
              decoration: _input(
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: AppColors.textSecondary),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                ),
              ),
              validator: (v) =>
                  AppValidators.confirmPassword(v, _passwordCtrl.text),
              onFieldSubmitted: (_) => _sendOtp(),
            ),
            if (_lockSecondsLeft > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                          color: AppColors.error, shape: BoxShape.circle),
                      child: const Icon(Icons.timer_rounded,
                          size: 14, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Too many attempts',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.error)),
                    ),
                    Text('$_lockSecondsLeft s',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.error)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 26),
            _PrimaryButton(
              label: 'Register',
              loading: isLoading,
              onPressed: isLoading || _resending || _verifying ? null : _sendOtp,
            ),
            const SizedBox(height: 14),
            _LinkRow(
              prompt: 'Already have an account?',
              action: 'Login',
              onPressed: () => context.go(RouteConstants.webLogin),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: OTP verification ──

  Widget _buildOtpStep() {
    final expired = _otpExpired || _secondsLeft == 0;
    return _AuthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Verify your email',
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
          const SizedBox(height: 8),
          Text(
            'Enter the 6-digit code we sent to ${AppValidators.normalizeEmail(_emailCtrl.text)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(6, (i) => _buildOtpBox(i)),
          ),
          const SizedBox(height: 14),
          if (_otpError != null)
            Text(_otpError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.error, height: 1.4))
          else
            Text(
              _lockSecondsLeft > 0
                  ? 'Locked for $_lockSecondsLeft seconds'
                  : expired
                      ? 'Code expired — resend to continue.'
                      : 'Code expires in $_secondsLeft seconds',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: _lockSecondsLeft > 0
                      ? AppColors.error
                      : AppColors.textSecondary),
            ),
          const SizedBox(height: 22),
          _PrimaryButton(
            label: 'Verify & Register',
            loading: _verifying,
            onPressed: (_verifying ||
                    _lockSecondsLeft > 0 ||
                    _otp.length != 6 ||
                    _otpExpired ||
                    _secondsLeft == 0)
                ? null
                : _verifyAndRegister,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: (_lockSecondsLeft == 0 && !_resending) ? _resendOtp : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 28, color: Color(0xFFECEEF3)),
          TextButton(
            onPressed: () {
              _resendTimer?.cancel();
              setState(() {
                _otpStep = false;
                _otpError = null;
                _otpExpired = false;
                _secondsLeft = 0;
              });
              for (final c in _otpControllers) {
                c.clear();
              }
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              foregroundColor: AppColors.textSecondary,
              shape: const RoundedRectangleBorder(),
            ),
            child: const Text('← Edit details',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    final hasError = _otpError != null;
    final locked = _lockSecondsLeft > 0;
    final expired = _otpExpired || (_secondsLeft == 0 && _otpStep);
    final invalid = hasError || expired;
    return SizedBox(
      width: 44,
      height: 52,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
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
          readOnly: locked || expired,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: invalid ? AppColors.error : AppColors.deepNavy),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: invalid
                ? AppColors.errorLight
                : const Color(0xFFF8F9FC),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: invalid ? AppColors.error : const Color(0xFFE4E7EE),
                  width: invalid ? 1.4 : 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: invalid ? AppColors.error : AppColors.deepNavy,
                  width: 1.6),
            ),
          ),
          onChanged: (v) => _onOtpChanged(index, v),
          onTap: () {
            _otpControllers[index].selection = TextSelection.fromPosition(TextPosition(offset: _otpControllers[index].text.length));
          },
        ),
      ),
    );
  }

  // ── Step 3: success ──

  Widget _buildSuccess() {
    return _AuthCard(
      child: Column(
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
            'Registration successful',
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
            'Your account has been created. You can now sign in to your workspace.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 26),
          _PrimaryButton(
            label: 'Back to Login',
            onPressed: () => context.go(RouteConstants.webLogin),
          ),
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Panel — light gradient surface hosting the centered card
// ─────────────────────────────────────────────────────────────────────────────

class _RegisterPanel extends StatelessWidget {
  final Widget child;
  final VoidCallback onBack;
  const _RegisterPanel({required this.child, required this.onBack});

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
          // faint gold glow echoing the login panel
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
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 72),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card + small shared pieces
// ─────────────────────────────────────────────────────────────────────────────

class _AuthCard extends StatelessWidget {
  final Widget child;
  const _AuthCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(36, 36, 36, 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECEEF3)),
        boxShadow: [
          BoxShadow(
              color: AppColors.deepNavy.withValues(alpha: 0.08),
              blurRadius: 36,
              offset: const Offset(0, 18)),
          BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

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
            color: isDisabled
                ? AppColors.deepNavy.withValues(alpha: 0.42)
                : null,
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
                  fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
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

class _LinkRow extends StatelessWidget {
  final String prompt;
  final String action;
  final VoidCallback onPressed;
  const _LinkRow({
    required this.prompt,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(prompt,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.textSecondary)),
        const SizedBox(width: 4),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            foregroundColor: AppColors.deepNavy,
            shape: const RoundedRectangleBorder(),
          ),
          child: Text(action,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
