// lib/presentation/features/auth/screens/otp_verify_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/legal_links.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class OtpVerifyScreen extends ConsumerStatefulWidget {
  final String phone;
  const OtpVerifyScreen({super.key, required this.phone});

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  Timer? _timer;
  int _secondsLeft = AppConstants.otpResendSeconds;
  Timer? _lockTimer;
  int _lockSecondsLeft = 0;
  bool _loading = false;
  String _otp = '';
  String? _error;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  void _startTimer() {
    setState(() => _secondsLeft = AppConstants.otpResendSeconds);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 0) {
        t.cancel();
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  void _startLockCountdown(int seconds) {
    _lockTimer?.cancel();
    setState(() {
      _lockSecondsLeft = seconds;
      _error = null;
    });
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_lockSecondsLeft <= 1) {
        t.cancel();
        if (mounted) setState(() => _lockSecondsLeft = 0);
      } else {
        if (mounted) setState(() => _lockSecondsLeft--);
      }
    });
    AppToast.showWidget(
      context,
      LockoutCountdownToast(
        seconds: seconds,
        onExpired: () {
          if (mounted) setState(() => _lockSecondsLeft = 0);
        },
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lockTimer?.cancel();
    _fadeController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(int index, String value) {
    if (_error != null) setState(() => _error = null);
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < digits.length && (index + i) < 6; i++) {
        _controllers[index + i].text = digits[i];
      }
      final next = (index + digits.length).clamp(0, 5);
      _focusNodes[next].requestFocus();
    } else if (value.isNotEmpty) {
      if (index < 5) _focusNodes[index + 1].requestFocus();
    } else if (index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    _updateOtp();
  }

  void _updateOtp() {
    final otp = _controllers.map((c) => c.text).join();
    setState(() => _otp = otp);
    if (otp.length == 6 && !otp.contains('')) _submit(otp);
  }

  Future<void> _submit([String? forcedOtp]) async {
    final otp = forcedOtp ?? _otp;
    if (otp.length != 6) {
      setState(() => _error = 'Please enter the complete 6-digit code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await ref
        .read(authProvider.notifier)
        .verifyOtp(phone: widget.phone, otp: otp);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      final state = ref.read(authStateProvider);
      if (state.forcePasswordChange) {
        final role = state.role;
        if (role == AppConstants.roleRider || role == AppConstants.roleLender) {
          switch (role) {
            case AppConstants.roleRider:
              context.go(RouteConstants.riderDashboard);
              break;
            case AppConstants.roleLender:
              context.go(RouteConstants.lenderDashboard);
              break;
            default:
              context.go(RouteConstants.mobileLogin);
          }
        } else {
          context.go(RouteConstants.forceChangePassword);
        }
      } else {
        final role = state.role;
        switch (role) {
          case AppConstants.roleRider:
            context.go(RouteConstants.riderDashboard);
            break;
          case AppConstants.roleLender:
            context.go(RouteConstants.lenderDashboard);
            break;
          default:
            context.go(RouteConstants.mobileLogin);
        }
      }
    } else {
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
      final err = ref.read(authProvider).error;
      var message = 'Invalid or expired code. Please try again.';
      if (err != null) {
        message =
            ref.read(authProvider.notifier).extractErrorMessage(err) ?? message;
      }
      final lockSecs =
          ref.read(authProvider.notifier).extractOtpLockoutSeconds(err ?? '');
      if (lockSecs != null && lockSecs > 0) {
        if (!mounted) return;
        setState(() {
          _error = message;
        });
        _startLockCountdown(lockSecs);
        return;
      }
      if (!mounted) return;
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _error = message);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _lockSecondsLeft > 0) return;
    final ok =
        await ref.read(authProvider.notifier).sendOtp(phone: widget.phone);
    if (!mounted) return;
    if (ok) {
      _startTimer();
      for (final c in _controllers) {
        c.clear();
      }
      setState(() {
        _error = null;
        _otp = '';
      });
      _focusNodes[0].requestFocus();
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Code resent to your Gmail and SMS. Please check your inbox.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final err = ref.read(authProvider).error;
      final lockSecs =
          ref.read(authProvider.notifier).extractOtpLockoutSeconds(err ?? '');
      if (lockSecs != null && lockSecs > 0) {
        _startLockCountdown(lockSecs);
        return;
      }
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(
            ref.read(authProvider.notifier).extractErrorMessage(err ?? '') ??
                'Failed to resend code.',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String get _lockLabel {
    final m = _lockSecondsLeft ~/ 60;
    final s = _lockSecondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final maskedPhone = widget.phone.length == 11
        ? '${widget.phone.substring(0, 4)} \u2022\u2022\u2022\u2022 ${widget.phone.substring(7)}'
        : widget.phone;
    final canVerify = _otp.length == 6 && !_loading && _lockSecondsLeft == 0;
    final canResend = _secondsLeft == 0 && _lockSecondsLeft == 0 && !_loading;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.white,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    children: [
                      // ── Scrollable area ──
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              // ── Header ──
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        _BackButton(
                                          onTap: () => context.go(RouteConstants.mobileLogin),
                                        ),
                                        const Spacer(),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    // Logo
                                    Container(
                                      width: 74,
                                      height: 74,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.deepNavy.withValues(alpha: 0.9),
                                          width: 2.4,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.18),
                                            blurRadius: 20,
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(3),
                                      child: ClipOval(
                                        child: Image.asset(
                                          AssetConstants.logoJpg,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(
                                            Icons.account_balance_rounded,
                                            color: AppColors.deepNavy,
                                            size: 34,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    const Text(
                                      'JIRETA',
                                      style: TextStyle(
                                        fontFamily: 'PlayfairDisplay',
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.deepNavy,
                                        letterSpacing: 6.5,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 68),
                                  ],
                                ),
                              ),

                              // ── Verify Code Card ──
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(
                                      color: AppColors.border,
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.deepNavy.withValues(alpha: 0.08),
                                        blurRadius: 32,
                                        offset: const Offset(0, 16),
                                      ),
                                      BoxShadow(
                                        color: AppColors.deepNavy.withValues(alpha: 0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        // Title
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Verify code',
                                              style: TextStyle(
                                                fontFamily: 'PlayfairDisplay',
                                                fontSize: 19,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.deepNavy,
                                                height: 1.1,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                          ],
                                        ),
                                        const SizedBox(height: 16),

                                        // Phone info (no box)
                                        Row(
                                          children: [
                                            const Icon(Icons.phone_rounded, size: 14, color: AppColors.deepNavy),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Code sent to',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.textTertiary,
                                                      letterSpacing: 0.4,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 1),
                                                  Text(
                                                    maskedPhone,
                                                    style: const TextStyle(
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: AppColors.deepNavy,
                                                      letterSpacing: 0.3,
                                                      fontFeatures: [FontFeature.tabularFigures()],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 22),

                                        // OTP boxes
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: List.generate(6, (i) => _buildOtpBox(i)),
                                        ),

                                        // Inline error
                                        if (_error != null && _lockSecondsLeft == 0) ...[
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _error!,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    color: AppColors.error,
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],

                                        // Lock countdown
                                        if (_lockSecondsLeft > 0) ...[
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              const Icon(Icons.timer_rounded, size: 15, color: AppColors.error),
                                              const SizedBox(width: 10),
                                              const Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Too many attempts',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w700,
                                                        color: AppColors.error,
                                                      ),
                                                    ),
                                                    Text(
                                                      'Please wait before trying again',
                                                      style: TextStyle(fontSize: 11, color: AppColors.error),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                _lockLabel,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.error,
                                                  fontFeatures: [FontFeature.tabularFigures()],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],

                                        const SizedBox(height: 20),

                                        // Verify CTA
                                        SizedBox(
                                          width: double.infinity,
                                          height: 54,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: canVerify
                                                  ? const LinearGradient(
                                                      colors: [AppColors.deepNavy, Color(0xFF1A3658)],
                                                      begin: Alignment.topLeft,
                                                      end: Alignment.bottomRight,
                                                    )
                                                  : null,
                                              color: canVerify ? null : const Color(0xFFE8E8EE),
                                              boxShadow: canVerify
                                                  ? [
                                                      BoxShadow(
                                                        color: AppColors.deepNavy.withValues(alpha: 0.32),
                                                        blurRadius: 16,
                                                        offset: const Offset(0, 8),
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                            child: ElevatedButton(
                                              onPressed: canVerify ? _submit : null,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                disabledBackgroundColor: Colors.transparent,
                                                disabledForegroundColor: AppColors.textTertiary.withValues(alpha: 0.6),
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                              ),
                                              child: _loading
                                                  ? const SizedBox(
                                                      height: 22,
                                                      width: 22,
                                                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                                    )
                                                  : Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          'Verify code',
                                                          style: TextStyle(
                                                            fontSize: 15.5,
                                                            fontWeight: FontWeight.w700,
                                                            letterSpacing: 0.2,
                                                            color: canVerify ? Colors.white : AppColors.textTertiary,
                                                          ),
                                                        ),
                                                        if (canVerify) ...[
                                                          const SizedBox(width: 8),
                                                          Container(
                                                            width: 22,
                                                            height: 22,
                                                            decoration: BoxDecoration(
                                                              color: Colors.white.withValues(alpha: 0.22),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),

                                        // Divider with label
                                        Row(
                                          children: [
                                            const Expanded(child: Divider(color: Color(0xFFE8E8EE), thickness: 1)),
                                            const Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 10),
                                              child: Text(
                                                'Having trouble?',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textTertiary,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ),
                                            const Expanded(child: Divider(color: Color(0xFFE8E8EE), thickness: 1)),
                                          ],
                                        ),
                                        const SizedBox(height: 14),

                                        // Resend row
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Text(
                                              "Didn't receive code?",
                                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                                            ),
                                            const SizedBox(width: 6),
                                            GestureDetector(
                                              onTap: canResend ? _resend : null,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: canResend ? AppColors.deepNavy : const Color(0xFFF0F0F3),
                                                  border: Border.all(
                                                    color: canResend ? AppColors.deepNavy : const Color(0xFFE8E8EE),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      _lockSecondsLeft > 0
                                                          ? 'Locked $_lockLabel'
                                                          : _secondsLeft > 0
                                                              ? 'Resend in ${_secondsLeft}s'
                                                              : 'Resend code',
                                                      style: TextStyle(
                                                        fontSize: 12.5,
                                                        fontWeight: FontWeight.w700,
                                                        letterSpacing: 0.2,
                                                        color: canResend ? Colors.white : AppColors.textTertiary,
                                                        fontFeatures: const [FontFeature.tabularFigures()],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),

                      // ── Footer (fixed at bottom) ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const LegalLinks(textColor: AppColors.textSecondary),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(width: 4, height: 4, decoration: BoxDecoration(color: AppColors.textTertiary.withValues(alpha: 0.45), shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Text(
                                  '\u00a9 1966  Jireta Loans & Credit Corp',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textTertiary.withValues(alpha: 0.9),
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(width: 4, height: 4, decoration: BoxDecoration(color: AppColors.textTertiary.withValues(alpha: 0.45), shape: BoxShape.circle)),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    final hasError = _error != null && _lockSecondsLeft == 0;
    final locked = _lockSecondsLeft > 0;
    final text = _controllers[index].text;
    final isFilled = text.isNotEmpty;
    final isFocused = _focusNodes[index].hasFocus;

    Color borderColor;
    double borderWidth;
    Color fillColor;
    if (hasError) {
      borderColor = AppColors.error;
      borderWidth = 1.6;
      fillColor = AppColors.errorLight;
    } else if (locked) {
      borderColor = const Color(0xFFE8E8EE);
      borderWidth = 1.1;
      fillColor = const Color(0xFFF0F0F3);
    } else if (isFocused) {
      borderColor = AppColors.deepNavy;
      borderWidth = 1.8;
      fillColor = Colors.white;
    } else if (isFilled) {
      borderColor = AppColors.deepNavy.withValues(alpha: 0.18);
      borderWidth = 1.4;
      fillColor = Colors.white;
    } else {
      borderColor = const Color(0xFFE8E8EE);
      borderWidth = 1.2;
      fillColor = const Color(0xFFF7F8FA);
    }

    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(left: index == 0 ? 0 : 5, right: index == 5 ? 0 : 5),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
              if (_controllers[index].text.isEmpty && index > 0) {
                _controllers[index - 1].clear();
                _focusNodes[index - 1].requestFocus();
                _updateOtp();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 44,
            decoration: BoxDecoration(
              color: fillColor,
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: isFocused && !hasError && !locked
                  ? [
                      BoxShadow(
                        color: AppColors.deepNavy.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: TextFormField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                readOnly: locked,
                enabled: !locked,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.deepNavy,
                  letterSpacing: 0.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (v) => _onChanged(index, v),
                onTap: () {
                  _controllers[index].selection = TextSelection.fromPosition(
                    TextPosition(offset: _controllers[index].text.length),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.deepNavy, size: 16),
        ),
      ),
    );
  }
}
