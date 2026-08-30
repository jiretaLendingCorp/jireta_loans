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
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  String _gender = 'male';
  String _civilStatus = 'single';
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
  String? _phoneDuplicationError;

  static const List<String> _genders = ['male', 'female', 'other'];
  static const List<String> _civilStatuses = [
    'single',
    'married',
    'widowed',
    'separated',
  ];

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
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
      _phoneDuplicationError = null;
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
      final isPhoneDup = repoError.toLowerCase().contains('phone') &&
          (repoError.toLowerCase().contains('already') || repoError.toLowerCase().contains('duplicate'));
      if (isEmailDup) {
        setState(() => _emailDuplicationError = AppValidators.duplicateEmailMessage);
        _formKey.currentState!.validate();
      }
      if (isPhoneDup) {
        setState(() => _phoneDuplicationError = 'Phone number already registered. Please use a different number.');
        _formKey.currentState!.validate();
      }
      // Rate limit / OTP lockout hint
      final lockSecs = ref.read(authProvider.notifier).extractOtpLockoutSeconds(repoError);
      if (lockSecs != null && lockSecs > 0) _startLockCountdown(lockSecs);

      context.showSnackBarAsToast(
        SnackBar(
          content: Text(repoError),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
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
          phoneNumber: _phoneCtrl.text.trim(),
          password: _passwordCtrl.text,
          gender: _gender,
          civilStatus: _civilStatus,
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
      final isPhoneDup = repoError.toLowerCase().contains('phone') &&
          (repoError.toLowerCase().contains('already') || repoError.toLowerCase().contains('duplicate'));
      if (isEmailDup) {
        setState(() => _emailDuplicationError = AppValidators.duplicateEmailMessage);
        setState(() => _otpStep = false);
        _formKey.currentState!.validate();
      }
      if (isPhoneDup) {
        setState(() => _phoneDuplicationError = 'Phone number already registered. Please use a different number.');
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
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(repoError),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
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
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: _submitted ? _buildSuccess() : (_otpStep ? _buildOtpStep() : _buildForm()),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final isLoading = _sendingOtp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Form(
          key: _formKey,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameCtrl,
                      maxLength: 50,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-']")),
                        LengthLimitingTextInputFormatter(50),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                        prefixIcon: Icon(Icons.person_outlined),
                        counterText: '',
                      ),
                      validator: (v) => AppValidators.required(v, 'First name'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameCtrl,
                      maxLength: 50,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-']")),
                        LengthLimitingTextInputFormatter(50),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Last Name',
                        counterText: '',
                      ),
                      validator: (v) => AppValidators.required(v, 'Last name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                maxLength: 254,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                inputFormatters: [LengthLimitingTextInputFormatter(254)],
                onChanged: (_) {
                  if (_emailDuplicationError != null) setState(() => _emailDuplicationError = null);
                },
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(Icons.email_outlined),
                  counterText: '',
                ),
                validator: (v) {
                  if (_emailDuplicationError != null) return _emailDuplicationError;
                  if (v == null || v.isEmpty) return 'Email is required';
                  if (!AppValidators.isValidEmail(v)) return 'Enter a valid email address';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 11,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                onChanged: (_) {
                  if (_phoneDuplicationError != null) setState(() => _phoneDuplicationError = null);
                },
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  counterText: '',
                  hintText: '09xxxxxxxxx',
                ),
                validator: (v) {
                  if (_phoneDuplicationError != null) return _phoneDuplicationError;
                  if (v == null || v.isEmpty) return 'Phone number is required';
                  if (!AppValidators.isValidPhone(v)) return 'Enter a valid PH phone number (e.g. 09xxxxxxxxx)';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
                      items: _genders.map((g) => DropdownMenuItem(value: g, child: Text(_capitalize(g)))).toList(),
                      onChanged: (v) => setState(() => _gender = v ?? _gender),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _civilStatus,
                      decoration: const InputDecoration(labelText: 'Civil Status', border: OutlineInputBorder()),
                      items: _civilStatuses.map((s) => DropdownMenuItem(value: s, child: Text(_capitalize(s)))).toList(),
                      onChanged: (v) => setState(() => _civilStatus = v ?? _civilStatus),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                maxLength: 64,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                inputFormatters: [LengthLimitingTextInputFormatter(64)],
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: AppValidators.password,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordCtrl,
                obscureText: _obscureConfirm,
                maxLength: 64,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                inputFormatters: [LengthLimitingTextInputFormatter(64)],
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) => AppValidators.confirmPassword(v, _passwordCtrl.text),
                onFieldSubmitted: (_) => _sendOtp(),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading || _resending || _verifying ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Register', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Already have an account? ', style: TextStyle(fontSize: 13)),
                    TextButton(onPressed: () => context.go(RouteConstants.webLogin), child: const Text('Login', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('Verify Your Email', style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.deepNavy)),
        const SizedBox(height: 8),
        Text('We sent a 6-digit code to ${AppValidators.normalizeEmail(_emailCtrl.text)}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        const Text('Enter the code below to create your account. Code expires in 1 minute.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.black, width: 1.4), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)), BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))]),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black, width: 1.2)),
                child: Row(
                  children: [
                    const Icon(Icons.email_outlined, size: 18, color: Colors.black),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Code sent to ${AppValidators.normalizeEmail(_emailCtrl.text)}', style: const TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                    if (_secondsLeft > 0) Text(' ${_secondsLeft}s', style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(6, (i) => _buildOtpBox(i))),
              if (_otpError != null) ...[
                const SizedBox(height: 8),
                Text(_otpError!, style: const TextStyle(fontSize: 12, color: AppColors.error), textAlign: TextAlign.center),
              ],
              if (_lockSecondsLeft > 0) ...[
                const SizedBox(height: 8),
                Text('Locked for $_lockSecondsLeft seconds', style: const TextStyle(fontSize: 12, color: Colors.orange)),
              ],
              if (_secondsLeft > 0 && _lockSecondsLeft == 0 && !_otpExpired)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text('Code expires in $_secondsLeft seconds', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: (_lockSecondsLeft == 0 && !_resending && _secondsLeft == 0 ? _resendOtp : _lockSecondsLeft == 0 && !_resending ? _resendOtp : null),
                    style: TextButton.styleFrom(backgroundColor: _resending ? Colors.white : null, side: _resending ? const BorderSide(color: Colors.black, width: 1.2) : null, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: _resending
                        ? const Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)), SizedBox(width: 6), Text('Sending...', style: TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.w600))])
                        : Text(_lockSecondsLeft > 0 ? 'Locked' : (_secondsLeft > 0 ? 'Resend Code' : 'Resend Code'), style: TextStyle(fontSize: 12, color: _lockSecondsLeft == 0 ? Colors.black : AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ),
                  ElevatedButton(
                    onPressed: (_verifying || _lockSecondsLeft > 0 || _otp.length != 6 || _otpExpired || _secondsLeft == 0) ? null : _verifyAndRegister,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: _verifying ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_otpExpired ? 'Expired' : 'Verify & Register', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Enter the 6-digit code to complete registration.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary), textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
          child: const Text('← Edit details', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildOtpBox(int index) {
    final hasError = _otpError != null;
    final locked = _lockSecondsLeft > 0;
    final expired = _otpExpired || (_secondsLeft == 0 && _otpStep);
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
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: hasError || expired ? AppColors.error : Colors.black),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: hasError || expired ? AppColors.error : Colors.black, width: 1.6)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: hasError || expired ? AppColors.error : Colors.black, width: 2.2)),
            filled: true,
            fillColor: hasError || expired ? AppColors.errorLight : Colors.white,
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
        const Text('Registration Successful!', style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.deepNavy)),
        const SizedBox(height: 8),
        const Text('Your account has been created successfully. You can now sign in.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6), textAlign: TextAlign.center),
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

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
