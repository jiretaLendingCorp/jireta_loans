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
  late final AppLifecycleListener _lifecycleListener;

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
    _lifecycleListener = AppLifecycleListener(onResume: _onAppResumed);
    // The splash screen used to gate first-run users through the Terms screen;
    // mobile now opens directly on this login screen, so check that gate here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstRun());
  }

  /// First-run terms gate: after the secure-storage session check settles and
  /// the user is confirmed logged out, send them to the Terms & Conditions
  /// screen until they have accepted it once.
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

  /// Resets the Google button when the user comes back from the browser flow
  /// without completing it (pressed back / cancelled). A short grace period
  /// lets a successful deep-link sign-in finish first — if it did, the router
  /// already redirected and this widget is unmounted, so nothing happens.
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildInfoMenuButton() {
    return PopupMenuButton<_InfoMenuAction>(
      tooltip: 'Menu',
      icon: const Icon(Icons.more_vert, color: AppColors.deepNavy, size: 22),
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 44),
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
              Icon(Icons.support_agent, color: AppColors.deepNavy, size: 20),
              SizedBox(width: 12),
              Text(
                'Help Center',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: _InfoMenuAction.about,
          child: Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.deepNavy, size: 20),
              SizedBox(width: 12),
              Text(
                'About Jireta',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: _InfoMenuAction.appVersion,
          child: Row(
            children: [
              Icon(Icons.verified_outlined,
                  color: AppColors.deepNavy, size: 20),
              SizedBox(width: 12),
              Text(
                'App Version',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
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
          icon: Icons.support_agent,
          faq: [
            _FaqItem(
              question: 'How do I log in to the app?',
              answer:
                  'Enter your registered mobile number and tap Send OTP. You will receive a one-time password (OTP) to verify your account.',
            ),
            _FaqItem(
              question: 'What if I do not receive my OTP?',
              answer:
                  'Wait at least 60 seconds before requesting a new OTP. Make sure your mobile number is correct and you have a stable connection.',
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
          icon: Icons.info_outline,
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

  @override
  Widget build(BuildContext context) {
    // While the secure-storage session check is running (or a session is being
    // restored), show a spinner instead of the login form so an already
    // signed-in user never flashes the login screen before the router
    // redirects them to their dashboard.
    final authState = ref.watch(authStateProvider);
    if (authState.isLoading || authState.isAuthenticated) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Live offline state: when connectivity drops, a persistent banner with a
    // spinner is rendered below the Continue with Google button and stays until
    // the connection is restored. The button gating below also reads this value
    // so the user cannot submit while offline.
    final isOnline = ref.watch(
      connectivityProvider.select((v) => v.valueOrNull ?? true),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight - 56,
                              ),
                              child: Center(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
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
                                        color: AppColors.textSecondary,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 48),
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border:
                                            Border.all(color: AppColors.border),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.deepNavy
                                                .withValues(alpha: 0.06),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                              prefixIcon:
                                                  Icon(Icons.phone_android),
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
                                                    const EdgeInsets.symmetric(
                                                        vertical: 16),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              child: _loading
                                                  ? const SizedBox(
                                                      height: 20,
                                                      width: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                  : const Text(
                                                      'Send OTP',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          const Divider(),
                                          const SizedBox(height: 16),
                                          OutlinedButton.icon(
                                            onPressed: (_loading ||
                                                    _googleLoading ||
                                                    !_isOnline)
                                                ? null
                                                : _signInWithGoogle,
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(
                                                  double.infinity, 52),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
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
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: AppColors.deepNavy,
                                                    ),
                                                  )
                                                : Image.network(
                                                    'https://www.google.com/favicon.ico',
                                                    width: 20,
                                                    height: 20,
                                                    errorBuilder: (_, __,
                                                            ___) =>
                                                        const Icon(
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
                          );
                        },
                      ),
                    ),
                  ),
                  if (!isOnline)
                    const Padding(
                      padding: EdgeInsets.only(left: 24, right: 24, bottom: 16),
                      child: OfflineToast(),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: LegalLinks(),
                  ),
                ],
              ),
              Positioned(
                top: 4,
                left: 4,
                child: _buildInfoMenuButton(),
              ),
            ],
          ),
        ),
      ),
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

/// A full-screen page used to display the Help Center (Q&A), About, and App
/// Version content. Pushed with [MaterialPageRoute] so it covers the whole
/// screen with an app bar at the top, instead of a bottom sheet.
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.deepNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Icon(icon, color: AppColors.gold, size: 20),
            const SizedBox(width: 8),
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
      color: AppColors.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
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
