// lib/presentation/features/auth/screens/mobile_login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../shared/providers/connectivity_provider.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/offline_toast.dart';
import '../providers/auth_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class MobileLoginScreen extends ConsumerStatefulWidget {
  const MobileLoginScreen({super.key});

  @override
  ConsumerState<MobileLoginScreen> createState() => _MobileLoginScreenState();
}

class _MobileLoginScreenState extends ConsumerState<MobileLoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  final _phoneMask = MaskTextInputFormatter(
    mask: '#### ### ####',
    filter: {'#': RegExp(r'[0-9]')},
  );
  bool _loading = false;
  bool _googleLoading = false;
  Timer? _lockTimer;
  int _lockSecondsLeft = 0;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));
    _fadeController.forward();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _fadeController.dispose();
    _lockTimer?.cancel();
    super.dispose();
  }

  String get _rawPhone => _phoneMask.getUnmaskedText();

  bool get _isPhoneValid =>
      _rawPhone.length == 11 && _rawPhone.startsWith('09');

  bool get _isOnline => ref.read(connectivityProvider).valueOrNull ?? true;

  /// Shows the remaining OTP-lock time (returned by the server) as a live
  /// countdown in a top-right toast while the Send OTP button stays disabled.
  void _startLockCountdown(int seconds) {
    _lockTimer?.cancel();
    setState(() => _lockSecondsLeft = seconds);
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_lockSecondsLeft <= 1) {
        t.cancel();
        setState(() => _lockSecondsLeft = 0);
      } else {
        setState(() => _lockSecondsLeft--);
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

  Future<void> _sendOtp() async {
    if (!_isOnline || _lockSecondsLeft > 0) return;
    if (!_isPhoneValid) {
      _showError('Enter a valid Philippine mobile number (09XXXXXXXXX).');
      return;
    }
    setState(() => _loading = true);
    final ok = await ref.read(authProvider.notifier).sendOtp(phone: _rawPhone);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      context.go(RouteConstants.otpVerify, extra: _rawPhone);
    } else {
      final err = ref.read(authProvider).error;
      // OTP lockout: show a live countdown instead of a one-off snackbar.
      final lockSecs =
          ref.read(authProvider.notifier).extractOtpLockoutSeconds(err ?? '');
      if (lockSecs != null && lockSecs > 0) {
        _startLockCountdown(lockSecs);
        return;
      }
      _showError(
        ref.read(authProvider.notifier).extractErrorMessage(err ?? '') ??
            'Failed to send OTP.',
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!_isOnline) return;
    if (_googleLoading || _loading) return;
    setState(() => _googleLoading = true);
    final ok = await ref.read(authProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    if (!ok) {
      final err = ref.read(authProvider).error;
      _showError(
        ref.read(authProvider.notifier).extractErrorMessage(err ?? '') ??
            'Google sign-in failed.',
      );
    }
  }

  void _showError(String msg) {
    context.showSnackBarAsToast(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Live offline state: when connectivity drops, a persistent banner with a
    // spinner is rendered below the Continue with Google button and stays until
    // the connection is restored. The button gating below also reads this value
    // so the user cannot submit while offline.
    final isOnline = ref.watch(
      connectivityProvider.select((v) => v.valueOrNull ?? true),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.navyOverlay,
      child: Scaffold(
        backgroundColor: AppColors.deepNavy,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 32),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.gold, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(AssetConstants.logoJpg,
                              fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'JIRETA',
                        style: TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          letterSpacing: 5,
                        ),
                      ),
                      const Text(
                        'LOANS & CREDIT CORP · 1966',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 48),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Login',
                              style: TextStyle(
                                fontFamily: 'PlayfairDisplay',
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppColors.deepNavy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Enter your mobile number to receive an OTP',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              maxLength: 13,
                              inputFormatters: [
                                // MaskTextInputFormatter already filters digits-only
                                // via filter: {'#': RegExp(r'[0-9]')}.
                                // Adding digitsOnly AFTER strips the spaces the mask
                                // inserts, causing an infinite reformatting loop.
                                _phoneMask,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Mobile Number',
                                hintText: '09XX XXX XXXX',
                                counterText: '',
                                prefixIcon: Icon(Icons.phone_android),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: (_isPhoneValid &&
                                        !_loading &&
                                        !_googleLoading &&
                                        _isOnline &&
                                        _lockSecondsLeft == 0)
                                    ? _sendOtp
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Send OTP',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed:
                                  (_loading || _googleLoading || !_isOnline)
                                      ? null
                                      : _signInWithGoogle,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: const BorderSide(
                                  color: AppColors.border,
                                  width: 1.5,
                                ),
                              ),
                              icon: _googleLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.deepNavy,
                                      ),
                                    )
                                  : Image.network(
                                      'https://www.google.com/favicon.ico',
                                      width: 20,
                                      height: 20,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.g_mobiledata,
                                          size: 24),
                                    ),
                              label: const Text(
                                'Continue with Google',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!isOnline)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(left: 24, right: 24, bottom: 24),
                    child: OfflineToast(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
