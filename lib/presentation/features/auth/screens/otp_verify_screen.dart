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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        ? '${widget.phone.substring(0, 4)} •••• ${widget.phone.substring(7)}'
        : widget.phone;
    final canVerify = _otp.length == 6 && !_loading && _lockSecondsLeft == 0;
    final canResend = _secondsLeft == 0 && _lockSecondsLeft == 0 && !_loading;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFFF6F7F9),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7F9),
        body: Stack(
          children: [
            // ── Premium navy header background ──
            Positioned.fill(
              child: Column(
                children: [
                  Container(
                    height: 330,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF0D1B2A),
                          Color(0xFF132A42),
                          Color(0xFF1A3658),
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Gold glow top-right
                        Positioned(
                          top: -60,
                          right: -40,
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.gold.withValues(alpha: 0.16),
                                  AppColors.gold.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Gold glow bottom-left
                        Positioned(
                          top: 110,
                          left: -50,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.gold.withValues(alpha: 0.09),
                                  AppColors.gold.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Subtle dots
                        Positioned(
                          top: 48,
                          right: 26,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 74,
                          right: 52,
                          child: Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 92,
                          left: 30,
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.28),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(color: const Color(0xFFF6F7F9)),
                  ),
                ],
              ),
            ),

            // ── Main content ──
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            children: [
                              // ── Header ──
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                                child: Column(
                                  children: [
                                    // Top bar — back button only (no secure badge)
                                    Row(
                                      children: [
                                        _BackButton(
                                          onTap: () => context.go(RouteConstants.mobileLogin),
                                        ),
                                        const Spacer(),
                                        // balance spacer to keep header centered visually
                                        const SizedBox(width: 40),
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
                                          color: AppColors.gold.withValues(alpha: 0.9),
                                          width: 2.4,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.18),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                          ),
                                          BoxShadow(
                                            color: AppColors.gold.withValues(alpha: 0.16),
                                            blurRadius: 24,
                                            offset: const Offset(0, 0),
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
                                        color: AppColors.gold,
                                        letterSpacing: 6.5,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      width: 32,
                                      height: 2,
                                      decoration: BoxDecoration(
                                        color: AppColors.gold.withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      'LOANS & CREDIT CORP  ·  SINCE 1966',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.70),
                                        letterSpacing: 2.2,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                  ],
                                ),
                              ),

                              // ── Premium Card ──
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Transform.translate(
                                  offset: const Offset(0, -10),
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(28),
                                      border: Border.all(color: Colors.white, width: 1),
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
                                          // Handle
                                          Center(
                                            child: Container(
                                              width: 36,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE8E8EE),
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 18),
                                          // Title row
                                          Row(
                                            children: [
                                              Container(
                                                width: 38,
                                                height: 38,
                                                decoration: BoxDecoration(
                                                  color: AppColors.deepNavy.withValues(alpha: 0.06),
                                                  borderRadius: BorderRadius.circular(11),
                                                  border: Border.all(
                                                    color: AppColors.deepNavy.withValues(alpha: 0.06),
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.mail_outline_rounded,
                                                  size: 18,
                                                  color: AppColors.deepNavy,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              const Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Verify code',
                                                      style: TextStyle(
                                                        fontFamily: 'PlayfairDisplay',
                                                        fontSize: 19,
                                                        fontWeight: FontWeight.w700,
                                                        color: AppColors.deepNavy,
                                                        height: 1.1,
                                                      ),
                                                    ),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'Enter the 6-digit code we sent you',
                                                      style: TextStyle(
                                                        fontSize: 12.5,
                                                        color: AppColors.textSecondary,
                                                        fontWeight: FontWeight.w500,
                                                        height: 1.2,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          // Phone pill + Gmail hint
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF7F8FA),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(color: const Color(0xFFE8E8EE)),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 30,
                                                  height: 30,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(9),
                                                    border: Border.all(color: const Color(0xFFE8E8EE)),
                                                  ),
                                                  child: const Icon(Icons.phone_rounded, size: 14, color: AppColors.deepNavy),
                                                ),
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
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.deepNavy,
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.alternate_email_rounded, size: 10, color: Colors.white),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        '& Gmail',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w700,
                                                          color: Colors.white,
                                                          letterSpacing: 0.3,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 22),

                                          // ── OTP boxes ──
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: List.generate(6, (i) => _buildOtpBox(i)),
                                          ),

                                          // Inline error (when not locked)
                                          if (_error != null && _lockSecondsLeft == 0) ...[
                                            const SizedBox(height: 14),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: AppColors.errorLight,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: AppColors.error.withValues(alpha: 0.14)),
                                              ),
                                              child: Row(
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
                                            ),
                                          ],

                                          // Lock countdown inline
                                          if (_lockSecondsLeft > 0) ...[
                                            const SizedBox(height: 14),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                              decoration: BoxDecoration(
                                                color: AppColors.errorLight,
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: AppColors.error.withValues(alpha: 0.16)),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 30,
                                                    height: 30,
                                                    decoration: const BoxDecoration(
                                                      color: AppColors.error,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(Icons.timer_rounded, size: 15, color: Colors.white),
                                                  ),
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
                                            ),
                                          ],

                                          const SizedBox(height: 20),

                                          // ── Premium Verify CTA ──
                                          SizedBox(
                                            width: double.infinity,
                                            height: 54,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: canVerify
                                                    ? const LinearGradient(
                                                        colors: [Color(0xFFC9A84C), Color(0xFFB8942E)],
                                                        begin: Alignment.topLeft,
                                                        end: Alignment.bottomRight,
                                                      )
                                                    : null,
                                                color: canVerify ? null : const Color(0xFFE8E8EE),
                                                borderRadius: BorderRadius.circular(14),
                                                boxShadow: canVerify
                                                    ? [
                                                        BoxShadow(
                                                          color: AppColors.gold.withValues(alpha: 0.32),
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
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

                                          // Helper hint
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.schedule_rounded, size: 11, color: AppColors.textTertiary.withValues(alpha: 0.9)),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Code expires in 5 minutes',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: AppColors.textTertiary.withValues(alpha: 0.95),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(width: 3, height: 3, decoration: BoxDecoration(color: AppColors.textTertiary.withValues(alpha: 0.45), shape: BoxShape.circle)),
                                              const SizedBox(width: 6),
                                              const Icon(Icons.mail_outline_rounded, size: 11, color: AppColors.textTertiary),
                                              const SizedBox(width: 4),
                                              const Text(
                                                'Check spam folder',
                                                style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 18),

                                          // Divider with label
                                          Row(
                                            children: [
                                              const Expanded(child: Divider(color: Color(0xFFE8E8EE), thickness: 1)),
                                              Container(
                                                margin: const EdgeInsets.symmetric(horizontal: 10),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF7F8FA),
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(color: const Color(0xFFE8E8EE)),
                                                ),
                                                child: const Text(
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
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(
                                                      color: canResend ? AppColors.deepNavy : const Color(0xFFE8E8EE),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        _lockSecondsLeft > 0
                                                            ? Icons.lock_rounded
                                                            : _secondsLeft > 0
                                                                ? Icons.hourglass_top_rounded
                                                                : Icons.send_rounded,
                                                        size: 13,
                                                        color: canResend ? Colors.white : AppColors.textTertiary,
                                                      ),
                                                      const SizedBox(width: 6),
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
                              ),

                              const SizedBox(height: 10),

                              // ── Footer ──
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                                child: Column(
                                  children: [
                                    const LegalLinks(textColor: AppColors.textSecondary),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(width: 4, height: 4, decoration: BoxDecoration(color: AppColors.textTertiary.withValues(alpha: 0.45), shape: BoxShape.circle)),
                                        const SizedBox(width: 8),
                                        Text(
                                          '© 1966  Jireta Loans & Credit Corp',
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
                                  ],
                                ),
                              ),
                              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
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
      borderColor = AppColors.gold;
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
            height: 56,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: isFocused && !hasError && !locked
                  ? [
                      BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.18),
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
                  fontSize: 22,
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
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}
