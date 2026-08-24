// lib/presentation/features/auth/screens/mobile_login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../../../shared/providers/connectivity_provider.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/offline_toast.dart';
import '../../../shared/widgets/legal_links.dart';
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
  bool _googleFlowCancelled = false;
  Timer? _lockTimer;
  int _lockSecondsLeft = 0;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();
    _lifecycleListener = AppLifecycleListener(onResume: _onAppResumed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstRun());
  }

  Future<void> _checkFirstRun() async {
    var authState = ref.read(authStateProvider);
    if (authState.isLoading) {
      for (var i = 0; i < 50 && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        authState = ref.read(authStateProvider);
        if (!authState.isLoading) break;
      }
    }
    if (!mounted || authState.isAuthenticated) return;
    final prefs = await SharedPreferences.getInstance();
    final termsAccepted = prefs.getBool(AppConstants.termsAcceptedKey) ?? false;
    if (mounted && !termsAccepted) {
      context.go(RouteConstants.terms);
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _fadeController.dispose();
    _lockTimer?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  String get _rawPhone => _phoneMask.getUnmaskedText();

  bool get _isPhoneValid =>
      _rawPhone.length == 11 && _rawPhone.startsWith('09');

  bool get _isOnline => ref.read(connectivityProvider).valueOrNull ?? true;

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
    _googleFlowCancelled = false;
    setState(() => _googleLoading = true);
    final ok = await ref.read(authProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    if (!ok && !_googleFlowCancelled) {
      final err = ref.read(authProvider).error;
      _showError(
        ref.read(authProvider.notifier).extractErrorMessage(err ?? '') ??
            'Google sign-in failed.',
      );
    }
  }

  void _onAppResumed() {
    if (!_googleLoading) return;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted || !_googleLoading) return;
      _googleFlowCancelled = true;
      ref.read(authProvider.notifier).cancelGoogleOAuth();
      setState(() => _googleLoading = false);
    });
  }

  void _showError(String msg) {
    context.showSnackBarAsToast(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildInfoMenuButton() {
    return PopupMenuButton<_InfoMenuAction>(
      tooltip: 'Menu',
      offset: const Offset(0, 48),
      color: Colors.white,
      elevation: 16,
      shadowColor: AppColors.deepNavy.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: const Icon(Icons.more_horiz_rounded,
            color: Colors.white, size: 20),
      ),
      onSelected: (action) {
        switch (action) {
          case _InfoMenuAction.helpCenter:
            _showHelpCenter();
          case _InfoMenuAction.about:
            _showAbout();
          case _InfoMenuAction.appVersion:
            _showAppVersion();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _InfoMenuAction.helpCenter,
          child: Row(
            children: [
              _MenuIcon(icon: Icons.support_agent_rounded),
              SizedBox(width: 12),
              Text('Help Center',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.deepNavy)),
            ],
          ),
        ),
        PopupMenuItem(
          value: _InfoMenuAction.about,
          child: Row(
            children: [
              _MenuIcon(icon: Icons.info_outline_rounded),
              SizedBox(width: 12),
              Text('About Jireta',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.deepNavy)),
            ],
          ),
        ),
        PopupMenuItem(
          value: _InfoMenuAction.appVersion,
          child: Row(
            children: [
              _MenuIcon(icon: Icons.verified_outlined),
              SizedBox(width: 12),
              Text('App Version',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.deepNavy)),
            ],
          ),
        ),
      ],
    );
  }

  void _showHelpCenter() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _InfoPage(
          title: 'Help Center',
          icon: Icons.support_agent_rounded,
          faq: [
            _FaqItem(
              question: 'How do I log in to the app?',
              answer:
                  'Enter your registered mobile number and tap Send OTP. You will receive a one-time password (OTP) on your Gmail and via SMS to verify your account.',
            ),
            _FaqItem(
              question: 'What if I do not receive my OTP?',
              answer:
                  'Wait at least 60 seconds before tapping Resend OTP. Check your Gmail inbox (including Spam) and SMS. Make sure your mobile number and Gmail on file are correct and you have a stable connection.',
            ),
            _FaqItem(
              question: 'How do I apply for a loan?',
              answer:
                  'After logging in, go to the Loans section and tap Apply. Fill out the required details and submit your application for review.',
            ),
            _FaqItem(
              question: 'What are the loan requirements?',
              answer:
                  'You need a valid government-issued ID, proof of billing, selfie verification, and proof of income. All documents are subject to verification.',
            ),
            _FaqItem(
              question: 'How do I pay for my loan?',
              answer:
                  'Payments can be made through GCash (via Xendit), office cash payment, or rider cash collection. A receipt is issued for every payment.',
            ),
            _FaqItem(
              question: 'Is my personal data safe?',
              answer:
                  'Yes. We protect your personal information in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173).',
            ),
            _FaqItem(
              question: 'Who can I contact for support?',
              answer:
                  'Visit our office during business hours or reach out to our authorized personnel. Never share your OTP or account credentials with anyone.',
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _InfoPage(
          title: 'About Jireta',
          icon: Icons.info_outline_rounded,
          sections: [
            _InfoSection(
              title: 'Company',
              body:
                  'Jireta Loans & Credit Corp 1966 is a lending company offering financial assistance to Filipinos.',
            ),
            _InfoSection(
              title: 'Our Services',
              body:
                  'We provide loans ranging from \u20B13,000 to \u20B1500,000 with clear terms and transparent interest rates.',
            ),
            _InfoSection(
              title: 'Our History',
              body:
                  'Founded in 1966, we have served our clients for decades with reliable and accessible lending services.',
            ),
            _InfoSection(
              title: 'Our Commitment',
              body:
                  'We are committed to providing fast, secure, and convenient loan processing through the mobile app.',
            ),
          ],
        ),
      ),
    );
  }

  void _showAppVersion() async {
    const packageName = 'com.example.jireta_loans';
    final marketUri = Uri.parse('market://details?id=$packageName');
    final playStoreUri =
        Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
    var launched = false;
    if (await canLaunchUrl(marketUri)) {
      launched =
          await launchUrl(marketUri, mode: LaunchMode.externalApplication);
    }
    if (!launched && await canLaunchUrl(playStoreUri)) {
      launched =
          await launchUrl(playStoreUri, mode: LaunchMode.externalApplication);
    }
    if (!launched) {
      _showError('Unable to open the Google Play Store.');
    }
  }

  String get _lockLabel {
    final m = _lockSecondsLeft ~/ 60;
    final s = _lockSecondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    if (authState.isLoading || authState.isAuthenticated) {
      return const Scaffold(
        backgroundColor: AppColors.deepNavy,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      );
    }

    final isOnline = ref.watch(
      connectivityProvider.select((v) => v.valueOrNull ?? true),
    );

    final canSendOtp = _isPhoneValid &&
        !_loading &&
        !_googleLoading &&
        isOnline &&
        _lockSecondsLeft == 0;

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
                    height: 360,
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
                                  AppColors.gold.withValues(alpha: 0.18),
                                  AppColors.gold.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Gold glow bottom-left
                        Positioned(
                          top: 120,
                          left: -50,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.gold.withValues(alpha: 0.10),
                                  AppColors.gold.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Subtle pattern circles
                        Positioned(
                          top: 40,
                          right: 28,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 72,
                          right: 56,
                          child: Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 95,
                          left: 32,
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.35),
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

            // ── Main scroll content ──
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
                              // ── Premium Brand Header ──
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 12, 24, 0),
                                child: Column(
                                  children: [
                                    // Top bar: menu right-aligned
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        // small badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.10),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.14)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF4CAF50),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'SECURE LOGIN',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 1.2,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.9),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        _buildInfoMenuButton(),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    // Logo
                                    Container(
                                      width: 78,
                                      height: 78,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.gold
                                              .withValues(alpha: 0.9),
                                          width: 2.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.18),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                          ),
                                          BoxShadow(
                                            color: AppColors.gold
                                                .withValues(alpha: 0.18),
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
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.account_balance_rounded,
                                            color: AppColors.deepNavy,
                                            size: 36,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // Brand name
                                    const Text(
                                      'JIRETA',
                                      style: TextStyle(
                                        fontFamily: 'PlayfairDisplay',
                                        fontSize: 30,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.gold,
                                        letterSpacing: 7,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      width: 36,
                                      height: 2,
                                      decoration: BoxDecoration(
                                        color: AppColors.gold
                                            .withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'LOANS & CREDIT CORP  ·  SINCE 1966',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white
                                            .withValues(alpha: 0.72),
                                        letterSpacing: 2.4,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.10)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.verified_user_rounded,
                                              size: 12,
                                              color: Colors.white
                                                  .withValues(alpha: 0.85)),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Trusted  •  Fast  •  Secure',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white
                                                  .withValues(alpha: 0.85),
                                              letterSpacing: 0.6,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 28),
                                  ],
                                ),
                              ),

                              // ── Premium Card (overlaps header) ──
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Transform.translate(
                                  offset: const Offset(0, -12),
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(28),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.deepNavy
                                              .withValues(alpha: 0.08),
                                          blurRadius: 32,
                                          offset: const Offset(0, 16),
                                        ),
                                        BoxShadow(
                                          color: AppColors.deepNavy
                                              .withValues(alpha: 0.04),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          24, 28, 24, 24),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          // Handle
                                          Center(
                                            child: Container(
                                              width: 36,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE8E8EE),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          // Title — reverted to Sign in
                                          Row(
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: AppColors.deepNavy
                                                      .withValues(alpha: 0.06),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: const Icon(
                                                  Icons.waving_hand_rounded,
                                                  size: 18,
                                                  color: AppColors.deepNavy,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              const Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Welcome back',
                                                      style: TextStyle(
                                                        fontFamily:
                                                            'PlayfairDisplay',
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            AppColors.deepNavy,
                                                        height: 1.1,
                                                      ),
                                                    ),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'Sign in to continue',
                                                      style: TextStyle(
                                                        fontSize: 12.5,
                                                        color: AppColors
                                                            .textSecondary,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 22),
                                          // Phone field label
                                          Row(
                                            children: [
                                              const Text(
                                                'Mobile Number',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.deepNavy,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.error
                                                      .withValues(alpha: 0.08),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Required',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.error,
                                                    letterSpacing: 0.4,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          // Premium input — simple (no extra smooth anim)
                                          TextFormField(
                                            controller: _phoneCtrl,
                                            keyboardType: TextInputType.phone,
                                            maxLength: 13,
                                            inputFormatters: [_phoneMask],
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.deepNavy,
                                              letterSpacing: 0.8,
                                            ),
                                            onChanged: (_) => setState(() {}),
                                            decoration: InputDecoration(
                                              hintText: '09XX XXX XXXX',
                                              hintStyle: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.textTertiary
                                                    .withValues(alpha: 0.7),
                                                letterSpacing: 0.6,
                                              ),
                                              counterText: '',
                                              filled: true,
                                              fillColor:
                                                  const Color(0xFFF7F8FA),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 16),
                                              prefixIcon: Padding(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                child: Container(
                                                  width: 38,
                                                  height: 38,
                                                  decoration: BoxDecoration(
                                                    color: _isPhoneValid
                                                        ? AppColors.deepNavy
                                                        : Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    border: Border.all(
                                                      color: _isPhoneValid
                                                          ? AppColors.deepNavy
                                                          : const Color(
                                                              0xFFE8E8EE),
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    Icons.phone_rounded,
                                                    size: 18,
                                                    color: _isPhoneValid
                                                        ? Colors.white
                                                        : AppColors
                                                            .textTertiary,
                                                  ),
                                                ),
                                              ),
                                              suffixIcon: _phoneCtrl
                                                      .text.isNotEmpty
                                                  ? Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              right: 12),
                                                      child: Icon(
                                                        _isPhoneValid
                                                            ? Icons
                                                                .check_circle_rounded
                                                            : Icons
                                                                .error_outline_rounded,
                                                        size: 20,
                                                        color: _isPhoneValid
                                                            ? const Color(
                                                                0xFF2E7D32)
                                                            : AppColors
                                                                .textTertiary
                                                                .withValues(
                                                                    alpha: 0.6),
                                                      ),
                                                    )
                                                  : null,
                                              suffixIconConstraints:
                                                  const BoxConstraints(
                                                      minWidth: 0,
                                                      minHeight: 0),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFFE8E8EE)),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                borderSide: const BorderSide(
                                                    color: AppColors.gold,
                                                    width: 1.7),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.lock_outline_rounded,
                                                size: 11,
                                                color: AppColors.textTertiary
                                                    .withValues(alpha: 0.9),
                                              ),
                                              const SizedBox(width: 4),
                                              const Expanded(
                                                child: Text(
                                                  'We’ll send a code to your Gmail & SMS',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color:
                                                        AppColors.textTertiary,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 22),

                                          // ── Lock countdown inline ──
                                          if (_lockSecondsLeft > 0)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  bottom: 14),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 12),
                                              decoration: BoxDecoration(
                                                color: AppColors.errorLight,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                    color: AppColors.error
                                                        .withValues(
                                                            alpha: 0.18)),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 28,
                                                    height: 28,
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: AppColors.error,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                        Icons.timer_rounded,
                                                        size: 14,
                                                        color: Colors.white),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Text(
                                                          'Too many attempts',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: AppColors
                                                                .error,
                                                          ),
                                                        ),
                                                        Text(
                                                          'Try again in $_lockLabel',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 11,
                                                            color: AppColors
                                                                .error,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Text(
                                                    _lockLabel,
                                                    style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: AppColors.error,
                                                      fontFeatures: [
                                                        FontFeature
                                                            .tabularFigures()
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                          // ── Premium CTA ──
                                          SizedBox(
                                            width: double.infinity,
                                            height: 54,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: canSendOtp
                                                    ? const LinearGradient(
                                                        colors: [
                                                          Color(0xFFC9A84C),
                                                          Color(0xFFB8942E),
                                                        ],
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                      )
                                                    : null,
                                                color: canSendOtp
                                                    ? null
                                                    : const Color(0xFFE8E8EE),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                boxShadow: canSendOtp
                                                    ? [
                                                        BoxShadow(
                                                          color: AppColors.gold
                                                              .withValues(
                                                                  alpha: 0.35),
                                                          blurRadius: 16,
                                                          offset:
                                                              const Offset(
                                                                  0, 8),
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                              child: ElevatedButton(
                                                onPressed: canSendOtp
                                                    ? _sendOtp
                                                    : null,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  shadowColor:
                                                      Colors.transparent,
                                                  disabledBackgroundColor:
                                                      Colors.transparent,
                                                  disabledForegroundColor:
                                                      AppColors.textTertiary
                                                          .withValues(
                                                              alpha: 0.6),
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14),
                                                  ),
                                                  padding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 20),
                                                ),
                                                child: _loading
                                                    ? const SizedBox(
                                                        height: 22,
                                                        width: 22,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2.4,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    : Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Text(
                                                            _lockSecondsLeft > 0
                                                                ? 'Locked · $_lockLabel'
                                                                : 'Send OTP',
                                                            style: TextStyle(
                                                              fontSize: 15.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              letterSpacing:
                                                                  0.3,
                                                              color: canSendOtp
                                                                  ? Colors.white
                                                                  : AppColors
                                                                      .textTertiary,
                                                            ),
                                                          ),
                                                          if (canSendOtp) ...[
                                                            const SizedBox(
                                                                width: 8),
                                                            Container(
                                                              width: 22,
                                                              height: 22,
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                        alpha:
                                                                            0.22),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                              child: const Icon(
                                                                Icons
                                                                    .arrow_forward_rounded,
                                                                size: 14,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 18),

                                          // Divider
                                          Row(
                                            children: [
                                              const Expanded(
                                                  child: Divider(
                                                      color:
                                                          Color(0xFFE8E8EE),
                                                      thickness: 1)),
                                              Container(
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFF7F8FA),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                      color: const Color(
                                                          0xFFE8E8EE)),
                                                ),
                                                child: const Text(
                                                  'or continue with',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        AppColors.textTertiary,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ),
                                              const Expanded(
                                                  child: Divider(
                                                      color:
                                                          Color(0xFFE8E8EE),
                                                      thickness: 1)),
                                            ],
                                          ),
                                          const SizedBox(height: 18),

                                          // Google button
                                          SizedBox(
                                            width: double.infinity,
                                            height: 52,
                                            child: OutlinedButton.icon(
                                              onPressed: (_loading ||
                                                      _googleLoading ||
                                                      !isOnline)
                                                  ? null
                                                  : _signInWithGoogle,
                                              style: OutlinedButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                foregroundColor:
                                                    AppColors.deepNavy,
                                                side: const BorderSide(
                                                    color: Color(0xFFE8E8EE),
                                                    width: 1.2),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                elevation: 0,
                                              ),
                                              icon: _googleLoading
                                                  ? const SizedBox(
                                                      height: 20,
                                                      width: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            AppColors.deepNavy,
                                                      ),
                                                    )
                                                  : Container(
                                                      width: 26,
                                                      height: 26,
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        border: Border.all(
                                                            color: const Color(
                                                                0xFFE8E8EE)),
                                                      ),
                                                      padding:
                                                          const EdgeInsets.all(
                                                              4),
                                                      child: Image.network(
                                                        'https://www.google.com/favicon.ico',
                                                        width: 18,
                                                        height: 18,
                                                        errorBuilder: (_,
                                                                __, ___) =>
                                                            const Icon(
                                                                Icons
                                                                    .g_mobiledata_rounded,
                                                                size: 20,
                                                                color: AppColors
                                                                    .deepNavy),
                                                      ),
                                                    ),
                                              label: const Text(
                                                'Continue with Google',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.deepNavy,
                                                  letterSpacing: 0.1,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 8),

                              // Offline banner
                              if (!isOnline)
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                                  child: OfflineToast(),
                                ),

                              // Legal + version footer
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 4, 20, 20),
                                child: Column(
                                  children: [
                                    const LegalLinks(
                                      textColor: AppColors.textSecondary,
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 4,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: AppColors.textTertiary
                                                .withValues(alpha: 0.5),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '© 1966  Jireta Loans & Credit Corp',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textTertiary
                                                .withValues(alpha: 0.9),
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 4,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: AppColors.textTertiary
                                                .withValues(alpha: 0.5),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                  height:
                                      MediaQuery.of(context).padding.bottom +
                                          8),
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
}

class _MenuIcon extends StatelessWidget {
  final IconData icon;
  const _MenuIcon({required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.deepNavy.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 15, color: AppColors.deepNavy),
    );
  }
}

enum _InfoMenuAction { helpCenter, about, appVersion }

class _InfoSection {
  final String title;
  final String body;
  const _InfoSection({required this.title, required this.body});
}

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});
}

class _InfoPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_InfoSection> sections;
  final List<_FaqItem> faq;

  const _InfoPage({
    required this.title,
    required this.icon,
    this.sections = const [],
    this.faq = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.deepNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.gold, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: faq.isNotEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Frequently Asked Questions',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.deepNavy,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final f in faq) _buildFaqTile(f),
                  const SizedBox(height: 8),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in sections) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Text(
                        s.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepNavy,
                        ),
                      ),
                    ),
                    Text(
                      s.body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildFaqTile(_FaqItem f) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE8E8EE)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: AppColors.deepNavy,
        collapsedIconColor: AppColors.deepNavy,
        title: Text(
          f.question,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.deepNavy,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              f.answer,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
