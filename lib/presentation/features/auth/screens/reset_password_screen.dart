// ignore_for_file: unnecessary_null_comparison, invalid_null_aware_operator, unnecessary_non_null_assertion
// lib/presentation/features/auth/screens/reset_password_screen.dart
// OTP-based password reset per spec:
// Forgot Password -> Email -> OTP (6-digit) -> Verify -> New Password -> Supabase Auth update
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

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _done = false;
  bool _otpVerified = false;
  bool _verifying = false;
  String? _otpError;
  String? _statusMsg;
  int _secondsLeft = 0;
  Timer? _resendTimer;
  int _lockSecondsLeft = 0;
  Timer? _lockTimer;
  bool _otpExpired = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      String? emailFromQuery;
      try {
        emailFromQuery = GoRouterState.of(context).uri.queryParameters['email'];
      } catch (_) {}
      emailFromQuery ??= Uri.base.queryParameters['email'];
      if (emailFromQuery != null && emailFromQuery.isNotEmpty) {
        _emailCtrl.text = Uri.decodeComponent(emailFromQuery);
        if (mounted) setState(() {});
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
            if (!_otpVerified) {
              _otpExpired = true;
              _otpError = 'OTP expired. Please tap Resend Code to get a new one.';
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
      if (!_otpVerified && !_otpExpired && _secondsLeft > 0 && _lockSecondsLeft == 0) _verifyOtp();
    }
  }

  Future<void> _verifyOtp() async {
    final email = _emailCtrl.text.trim();
    final otp = _otp;
    if (email.isEmpty) {
      setState(() => _otpError = 'No email found. Go back to Forgot Password and send code again.');
      return;
    }
    if (!AppValidators.isValidEmail(email)) {
      setState(() => _otpError = 'Invalid email format.');
      return;
    }
    if (otp.length != 6) {
      setState(() => _otpError = 'Enter 6-digit code');
      return;
    }
    if (_lockSecondsLeft > 0) return;
    if (_otpExpired) {
      setState(() => _otpError = 'OTP expired. Please tap Resend Code to get a new one.');
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
    final ok = await ref.read(authProvider.notifier).verifyResetOtp(email: email, otp: otp);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (ok) {
      _resendTimer?.cancel();
      setState(() => _otpVerified = true);
      context.showSnackBarAsToast(
        const SnackBar(content: Text('OTP verified. Set your new password.'), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating),
      );
    } else {
      final err = ref.read(authProvider).error;
      final msg = ref.read(authProvider.notifier).extractErrorMessage(err ?? '') ?? 'Invalid or expired OTP';
      final lockSecs = ref.read(authProvider.notifier).extractOtpLockoutSeconds(err ?? '');
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
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      context.showSnackBarAsToast(const SnackBar(content: Text('No email found. Go back to Forgot Password.'), backgroundColor: AppColors.error));
      return;
    }
    if (!AppValidators.isValidEmail(email)) {
      context.showSnackBarAsToast(const SnackBar(content: Text('Invalid email format.'), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _resending = true);
    final ok = await ref.read(authProvider.notifier).forgotPassword(email: email);
    if (!mounted) return;
    setState(() => _resending = false);
    if (ok) {
      _startResendTimer();
      for (final c in _otpControllers) {
        c.clear();
      }
      setState(() {
        _otpError = null;
        _otpVerified = false;
      });
      _otpFocus[0].requestFocus();
      // White indication that OTP was resent (vibrant white card with black text)
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
      final err = ref.read(authProvider).error;
      final msg = ref.read(authProvider.notifier).extractErrorMessage(err ?? '') ?? 'Failed to resend code';
      final lockSecs = ref.read(authProvider.notifier).extractOtpLockoutSeconds(err ?? '');
      if (lockSecs != null && lockSecs > 0) _startLockCountdown(lockSecs);
      context.showSnackBarAsToast(SnackBar(content: Text(msg), backgroundColor: AppColors.error));
    }
  }

  Future<void> _submitNewPassword() async {
    if (!_otpVerified) {
      context.showSnackBarAsToast(const SnackBar(content: Text('Please verify OTP first'), backgroundColor: AppColors.error));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final otp = _otp;
    // Defensive: OTP should still be present from Step 1 (hidden after verified). If empty, force re-verify.
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
      context.showSnackBarAsToast(const SnackBar(content: Text('OTP expired. Please resend and verify again.'), backgroundColor: AppColors.error));
      return;
    }
    final newPassword = _newCtrl.text;
    final notifier = ref.read(authProvider.notifier);
    final ok = await notifier.resetPassword(email: email, otp: otp, newPassword: newPassword);
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
      final msg = notifier.extractErrorMessage(err ?? '') ?? 'Failed to reset password. Check OTP or try again.';
      // If backend says OTP invalid/expired even though we were verified, the 1-minute window likely elapsed
      // before reset (now extended to 10 min after verify). Treat as session expired and bounce back to Step 1.
      final isOtpError = msg.toLowerCase().contains('otp') || msg.toLowerCase().contains('expired') || msg.toLowerCase().contains('invalid');
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
      context.showSnackBarAsToast(SnackBar(content: Text(msg), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary), onPressed: () => context.go(RouteConstants.webLogin)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: _done ? _buildSuccess() : _buildForm(isLoading),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool isLoading) {
    return Column(
      children: [
        Text(
          _otpVerified ? 'Set New Password' : 'Reset Password',
          style: const TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          _otpVerified ? 'Create your new password.' : 'Enter the 6-digit code sent to your email.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(20)),
            border: Border.fromBorderSide(BorderSide(color: Colors.black, width: 1.4)),
            boxShadow: [
              BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)),
              BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // ── STEP 1: OTP only (email already provided from Forgot Password) ──
                if (!_otpVerified) ...[
                  if (_emailCtrl.text.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black, width: 1.2)),
                      child: Row(
                        children: [
                          const Icon(Icons.email_outlined, size: 18, color: Colors.black),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Code sent to ${_emailCtrl.text}', style: const TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.error)),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                              SizedBox(width: 8),
                              Expanded(child: Text('No email found. Enter your email to receive code.', style: TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(fontWeight: FontWeight.w400, color: Colors.black),
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            labelStyle: TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                            floatingLabelStyle: TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                            prefixIcon: Icon(Icons.email_outlined, color: Colors.black),
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.black, width: 1.4)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.black, width: 1.4)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.black, width: 2)),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (!AppValidators.isValidEmail(v)) return 'Invalid email';
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  // OTP Boxes
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, (i) => _buildOtpBox(i)),
                  ),
                  if (_otpError != null) ...[
                    const SizedBox(height: 8),
                    Text(_otpError!, style: const TextStyle(fontSize: 12, color: AppColors.error), textAlign: TextAlign.center),
                  ],
                  if (_lockSecondsLeft > 0) ...[
                    const SizedBox(height: 8),
                    Text('Locked for $_lockSecondsLeft seconds', style: const TextStyle(fontSize: 12, color: Colors.orange)),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: (_lockSecondsLeft == 0 && !_resending) ? _resendOtp : null,
                        style: TextButton.styleFrom(
                          backgroundColor: _resending ? Colors.white : null,
                          side: _resending ? const BorderSide(color: Colors.black, width: 1.2) : null,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _resending
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)),
                                  SizedBox(width: 6),
                                  Text('Sending...', style: TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.w600)),
                                ],
                              )
                            : Text(
                                _lockSecondsLeft > 0 ? 'Locked' : 'Resend Code',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _lockSecondsLeft == 0 ? Colors.black : AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      ElevatedButton(
                        onPressed: (_verifying || _lockSecondsLeft > 0 || _otp.length != 6 || _otpExpired || _secondsLeft == 0) ? null : _verifyOtp,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _verifying
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(_otpExpired ? 'Expired' : 'Verify OTP', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the 6-digit code to continue.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],

                // ── STEP 2: Password form (shown only after OTP verified, email hidden) ──
                if (_otpVerified) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.success)),
                    child: const Row(
                      children: [
                        Icon(Icons.verified_user, color: AppColors.success, size: 20),
                        SizedBox(width: 8),
                        Expanded(child: Text('OTP verified ✓', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _currentCtrl,
                    obscureText: _obscureCurrent,
                    maxLength: 128,
                    style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      labelStyle: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                      floatingLabelStyle: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                      hintText: 'Enter current password',
                      hintStyle: const TextStyle(fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.black),
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(_obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.black),
                        onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 1.4)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 2)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 1.4)),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length < 8) return 'At least 8 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newCtrl,
                    obscureText: _obscureNew,
                    maxLength: 128,
                    style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                    onChanged: (_) {
                      if (_confirmCtrl.text.isNotEmpty) {
                        _formKey.currentState?.validate();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      labelStyle: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                      floatingLabelStyle: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                      prefixIcon: const Icon(Icons.lock_outlined, color: Colors.black),
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.black),
                        onPressed: () => setState(() => _obscureNew = !_obscureNew),
                      ),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 1.4)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 2)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 1.4)),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length < 8) return 'At least 8 characters';
                      if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Include uppercase';
                      if (!RegExp(r'[a-z]').hasMatch(v)) return 'Include lowercase';
                      if (!RegExp(r'[0-9]').hasMatch(v)) return 'Include number';
                      if (_currentCtrl.text.isNotEmpty && v == _currentCtrl.text) return 'New password must differ from current';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: _obscureConfirm,
                    maxLength: 128,
                    style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      labelStyle: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                      floatingLabelStyle: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                      prefixIcon: const Icon(Icons.lock_outlined, color: Colors.black),
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.black),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 1.4)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 2)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 1.4)),
                    ),
                    validator: (v) {
                      if (v != _newCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (isLoading || _lockSecondsLeft > 0) ? null : _submitNewPassword,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Change Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (_statusMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(_statusMsg!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _otpVerified = false;
                      });
                    },
                    child: const Text('← Back to verification', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpBox(int index) {
    final hasError = _otpError != null;
    final locked = _lockSecondsLeft > 0;
    final verified = _otpVerified;
    final expired = _otpExpired || (_secondsLeft == 0 && !_otpVerified);
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
          readOnly: locked || verified || expired,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: verified ? AppColors.success : expired ? AppColors.error : Colors.black),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: verified ? AppColors.success : hasError || expired ? AppColors.error : Colors.black, width: 1.6),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: verified ? AppColors.success : hasError || expired ? AppColors.error : Colors.black, width: 2.2),
            ),
            filled: true,
            fillColor: verified ? AppColors.successLight : hasError || expired ? AppColors.errorLight : Colors.white,
          ),
          onChanged: (v) => _onOtpChanged(index, v),
          onTap: () {
            _otpControllers[index].selection = TextSelection.fromPosition(TextPosition(offset: _otpControllers[index].text.length));
          },
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        Container(width: 80, height: 80, decoration: const BoxDecoration(color: AppColors.successLight, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.success, width: 1.5))), child: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 44)),
        const SizedBox(height: 20),
        const Text('Password Reset!', style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 26, fontWeight: FontWeight.w800, color: Colors.black)),
        const SizedBox(height: 8),
        const Text('Your password has been updated successfully. Please log in with your new password.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600, height: 1.6), textAlign: TextAlign.center),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.go(RouteConstants.webLogin),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.deepNavy, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Back to Login', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
