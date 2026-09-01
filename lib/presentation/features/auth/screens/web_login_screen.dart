// lib/presentation/features/auth/screens/web_login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../../../shared/providers/connectivity_provider.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/offline_toast.dart';
import '../providers/auth_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class WebLoginScreen extends ConsumerStatefulWidget {
  const WebLoginScreen({super.key});

  @override
  ConsumerState<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends ConsumerState<WebLoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _obscure = true;
  Timer? _lockTimer;
  int _lockSecondsLeft = 0;

  late final AnimationController _pageCtrl;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;
  late final Animation<double> _bgFade;

  @override
  void initState() {
    super.initState();
    _pageCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _cardFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _pageCtrl, curve: const Interval(0.18, 0.82, curve: Curves.easeOutCubic)),
    );
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(parent: _pageCtrl, curve: const Interval(0.18, 0.82, curve: Curves.easeOutCubic)),
    );
    _bgFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _pageCtrl, curve: const Interval(0.0, 0.45, curve: Curves.easeOut)),
    );
    // small delay so header animates first, then body
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _pageCtrl.forward();
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _lockTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  bool get _isOnline => ref.read(connectivityProvider).valueOrNull ?? true;

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

  Future<void> _submit() async {
    if (ref.read(authProvider).isLoading) return;
    if (_lockSecondsLeft > 0) return;
    if (!_isOnline) {
      _showNoInternetToast();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authProvider.notifier);
    final ok = await notifier.login(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (ok && mounted) {
      _goToRoleHome();
      return;
    }
    if (!ok && mounted) {
      final err = ref.read(authProvider).error;
      final lockSecs = notifier.extractOtpLockoutSeconds(err ?? '');
      if (lockSecs != null && lockSecs > 0) {
        _startLockCountdown(lockSecs);
        return;
      }
      _showError(notifier.extractErrorMessage(err ?? 'Error') ?? 'Login failed.');
    }
  }

  void _goToRoleHome() {
    final role = ref.read(authStateProvider).role;
    switch (role) {
      case AppConstants.roleHeadManager:
        context.go(RouteConstants.hmDashboard);
      case AppConstants.roleEmployee:
        context.go(RouteConstants.empDashboard);
      case AppConstants.roleRider:
        context.go(RouteConstants.riderDashboard);
      case AppConstants.roleLender:
        context.go(RouteConstants.lenderDashboard);
      default:
        context.go(RouteConstants.webLogin);
    }
  }

  void _showNoInternetToast() {
    if (!mounted) return;
    AppToast.show(context, 'No Internet Connection', type: AppToastType.info);
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

  String get _lockLabel {
    final m = _lockSecondsLeft ~/ 60;
    final s = _lockSecondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      connectivityProvider.select((v) => v.valueOrNull ?? true),
      (previous, next) {
        if (previous == true && next == false) _showNoInternetToast();
      },
    );
    final isLoading = ref.watch(authProvider).isLoading;
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: Stack(
        children: [
          // ── Premium background blobs (animated fade) ──
          Positioned.fill(
            child: FadeTransition(
              opacity: _bgFade,
              child: const _PremiumBackground(),
            ),
          ),
          // Centered login card — no header/footer (removed per spec #4)
          Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: FadeTransition(
                  opacity: _cardFade,
                  child: SlideTransition(
                    position: _cardSlide,
                    child: _PremiumLoginCard(
                      formKey: _formKey,
                      emailCtrl: _emailCtrl,
                      passCtrl: _passCtrl,
                      emailFocus: _emailFocus,
                      passFocus: _passFocus,
                      obscure: _obscure,
                      onToggleObscure: () => setState(() => _obscure = !_obscure),
                      onSubmit: _submit,
                      isLoading: isLoading,
                      isOnline: isOnline,
                      lockSecondsLeft: _lockSecondsLeft,
                      lockLabel: _lockLabel,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!isOnline)
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(left: 24, right: 24, bottom: 18),
                child: OfflineToast(),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium background
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradient UI — soft mesh gradient (gold → navy tint)
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFCFBF7), // warm gold tint
                Color(0xFFF8F9FB), // base
                Color(0xFFEFF2F8), // cool navy tint
                Color(0xFFF6F0E0), // gold wash at bottom
              ],
              stops: [0.0, 0.38, 0.72, 1.0],
            ),
          ),
        ),
        // gold glow top-right — stronger for gradient feel
        Positioned(
          top: -60,
          right: -40,
          child: Container(
            width: 480,
            height: 480,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AppColors.gold.withValues(alpha: 0.10), AppColors.gold.withValues(alpha: 0.0)],
              ),
            ),
          ),
        ),
        // navy glow bottom-left
        Positioned(
          bottom: -90,
          left: -70,
          child: Container(
            width: 560,
            height: 560,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AppColors.deepNavy.withValues(alpha: 0.07), AppColors.deepNavy.withValues(alpha: 0.0)],
              ),
            ),
          ),
        ),
        // secondary gold wash center
        Positioned(
          top: 180,
          left: -80,
          child: Container(
            width: 380,
            height: 380,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AppColors.gold.withValues(alpha: 0.04), AppColors.gold.withValues(alpha: 0.0)],
              ),
            ),
          ),
        ),
        // dotted pattern top
        Positioned(
          top: 28,
          right: 36,
          child: _DotGrid(color: AppColors.deepNavy.withValues(alpha: 0.05)),
        ),
        // subtle bottom gradient line
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 1,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, AppColors.gold.withValues(alpha: 0.12), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DotGrid extends StatelessWidget {
  final Color color;
  const _DotGrid({required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: List.generate(
              6,
              (_) => Container(
                width: 3, height: 3,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium hero — no feature chips, no "manage applications / collections" text
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumHero extends StatefulWidget {
  final bool alignCenter;
  const _PremiumHero({required this.alignCenter});

  @override
  State<_PremiumHero> createState() => _PremiumHeroState();
}

class _PremiumHeroState extends State<_PremiumHero> with SingleTickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
    _floatAnim = Tween<double>(begin: 0, end: 6).animate(CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));
    _floatCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final align = widget.alignCenter ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = widget.alignCenter ? TextAlign.center : TextAlign.left;

    return Column(
      crossAxisAlignment: align,
      children: [
        // Eyebrow pill with subtle scale-in
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.94, end: 1.0),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                const Text('STAFF PORTAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppColors.deepNavy)),
                const SizedBox(width: 7),
                Container(width: 1, height: 10, color: AppColors.border),
                const SizedBox(width: 7),
                Text('SINCE 1966', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.textTertiary.withValues(alpha: 0.9))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Welcome back',
          textAlign: textAlign,
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: widget.alignCenter ? 30 : 36,
            fontWeight: FontWeight.w700,
            color: AppColors.deepNavy,
            height: 1.1,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Sign in to continue to your workspace.',
          textAlign: textAlign,
          style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.textSecondary, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 26),
        // Premium visual card — floating animation
        AnimatedBuilder(
          animation: _floatAnim,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, -_floatAnim.value * 0.35),
            child: child,
          ),
          child: Container(
            width: widget.alignCenter ? 360 : double.infinity,
            constraints: const BoxConstraints(maxWidth: 440),
            height: widget.alignCenter ? 200 : 228,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D1B2A), Color(0xFF132A42), Color(0xFF1B3658)],
              ),
              boxShadow: [
                BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.18), blurRadius: 28, offset: const Offset(0, 14)),
                BoxShadow(color: AppColors.gold.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 0)),
              ],
            ),
            child: Stack(
              children: [
                // gold glow
                Positioned(
                  top: -30, right: -30,
                  child: Container(
                    width: 160, height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [AppColors.gold.withValues(alpha: 0.14), AppColors.gold.withValues(alpha: 0.0)]),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -20, left: -20,
                  child: Container(
                    width: 140, height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.0)]),
                    ),
                  ),
                ),
                // content centered
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.95), width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 6))],
                        ),
                        padding: const EdgeInsets.all(2.5),
                        child: ClipOval(
                          child: Image.asset(AssetConstants.logoJpg, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_rounded, color: AppColors.deepNavy, size: 28)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('JIRETA', style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.gold, letterSpacing: 4.5, height: 1)),
                      const SizedBox(height: 6),
                      Container(width: 28, height: 2, decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(1))),
                      const SizedBox(height: 8),
                      Text('LOANS & CREDIT CORP', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.8, color: Colors.white.withValues(alpha: 0.88))),
                      const SizedBox(height: 3),
                      Text('Est. 1966 · Philippines', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.6, color: Colors.white.withValues(alpha: 0.55))),
                    ],
                  ),
                ),
                // subtle bottom line
                Positioned(
                  left: 18, right: 18, bottom: 14,
                  child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0.0), Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.0)]))),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        // Divider + caption — premium, minimal
        Container(
          width: 36, height: 2,
          decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(1)),
        ),
        const SizedBox(height: 10),
        Text(
          'Trusted lending partner for generations.',
          textAlign: textAlign,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, letterSpacing: 0.2, color: AppColors.textTertiary.withValues(alpha: 0.95)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium login card — modern animated interactions
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumLoginCard extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final FocusNode emailFocus;
  final FocusNode passFocus;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final bool isLoading;
  final bool isOnline;
  final int lockSecondsLeft;
  final String lockLabel;

  const _PremiumLoginCard({
    required this.formKey,
    required this.emailCtrl,
    required this.passCtrl,
    required this.emailFocus,
    required this.passFocus,
    required this.obscure,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.isLoading,
    required this.isOnline,
    required this.lockSecondsLeft,
    required this.lockLabel,
  });

  @override
  State<_PremiumLoginCard> createState() => _PremiumLoginCardState();
}

class _PremiumLoginCardState extends State<_PremiumLoginCard> {
  bool _btnHovered = false;
  bool _emailHovered = false;
  bool _passHovered = false;

  @override
  Widget build(BuildContext context) {
    final isLocked = widget.lockSecondsLeft > 0;
    final isDisabled = widget.isLoading || !widget.isOnline || isLocked;

    return Container(
      decoration: BoxDecoration(
        // Gradient UI card — white to warm gold wash
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFFFFBF0)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9E9EE)),
        boxShadow: [
          BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.08), blurRadius: 32, offset: const Offset(0, 16)),
          BoxShadow(color: AppColors.gold.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
          BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // gradient top accent — gold → navy
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFFC9A84C), Color(0xFFE0C270), Color(0xFFC9A84C)]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
              child: Form(
                key: widget.formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header — Sign in at left upper corner as requested
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sign in', style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.deepNavy, height: 1.1, letterSpacing: -0.2)),
                          const SizedBox(height: 4),
                          const Text('Access your account to continue', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
                          const SizedBox(height: 12),
                          Container(
                            width: 32, height: 2.5,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [Color(0xFFC9A84C), Color(0xFFE0C270), Color(0xFFC9A84C)]),
                              borderRadius: BorderRadius.all(Radius.circular(2)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Email — staggered
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 480),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Email Address', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          const SizedBox(height: 8),
                          MouseRegion(
                            onEnter: (_) => setState(() => _emailHovered = true),
                            onExit: (_) => setState(() => _emailHovered = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: widget.emailFocus.hasFocus || _emailHovered
                                    ? [BoxShadow(color: AppColors.gold.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 4))]
                                    : [],
                              ),
                              child: TextFormField(
                                controller: widget.emailCtrl,
                                focusNode: widget.emailFocus,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                maxLength: 254,
                                readOnly: isLocked,
                                onTap: () => setState(() {}),
                                onChanged: (_) => setState(() {}),
                                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                                decoration: InputDecoration(
                                  hintText: 'you@example.com',
                                  hintStyle: TextStyle(fontSize: 13.5, color: AppColors.textTertiary.withValues(alpha: 0.75)),
                                  prefixIcon: Icon(Icons.mail_outlined, size: 18, color: widget.emailFocus.hasFocus ? AppColors.gold : AppColors.textTertiary),
                                  counterText: '',
                                  filled: true,
                                  fillColor: widget.emailFocus.hasFocus ? Colors.white : const Color(0xFFFAFAFC),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _emailHovered ? const Color(0xFFE0E0E8) : const Color(0xFFE9E9EE))),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 1.6)),
                                  errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error)),
                                  focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.6)),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Email is required';
                                  if (!AppValidators.isValidEmail(v)) return 'Enter a valid email';
                                  return null;
                                },
                                onFieldSubmitted: (_) => widget.passFocus.requestFocus(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Password — staggered 80ms later
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 560),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Password', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          const SizedBox(height: 8),
                          MouseRegion(
                            onEnter: (_) => setState(() => _passHovered = true),
                            onExit: (_) => setState(() => _passHovered = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: widget.passFocus.hasFocus || _passHovered
                                    ? [BoxShadow(color: AppColors.gold.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 4))]
                                    : [],
                              ),
                              child: TextFormField(
                                controller: widget.passCtrl,
                                focusNode: widget.passFocus,
                                obscureText: widget.obscure,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                maxLength: 128,
                                readOnly: isLocked,
                                onTap: () => setState(() {}),
                                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                                decoration: InputDecoration(
                                  hintText: '••••••••',
                                  hintStyle: TextStyle(fontSize: 13.5, color: AppColors.textTertiary.withValues(alpha: 0.75)),
                                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 18, color: widget.passFocus.hasFocus ? AppColors.gold : AppColors.textTertiary),
                                  counterText: '',
                                  filled: true,
                                  fillColor: widget.passFocus.hasFocus ? Colors.white : const Color(0xFFFAFAFC),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _passHovered ? const Color(0xFFE0E0E8) : const Color(0xFFE9E9EE))),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 1.6)),
                                  errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error)),
                                  focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.6)),
                                  suffixIcon: IconButton(
                                    icon: Icon(widget.obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: AppColors.textSecondary),
                                    onPressed: widget.onToggleObscure,
                                    tooltip: widget.obscure ? 'Show password' : 'Hide password',
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Password is required';
                                  return null;
                                },
                                onFieldSubmitted: (_) => widget.onSubmit(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => context.go(RouteConstants.forgotPassword),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), foregroundColor: AppColors.deepNavy),
                        child: const Text('Forgot password?', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (isLocked)
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child)),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.error.withValues(alpha: 0.16))),
                          child: Row(
                            children: [
                              Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle), child: const Icon(Icons.timer_rounded, size: 14, color: Colors.white)),
                              const SizedBox(width: 10),
                              const Expanded(child: Text('Too many attempts. Try again in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error))),
                              Text(widget.lockLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.error, fontFeatures: [FontFeature.tabularFigures()])),
                            ],
                          ),
                        ),
                      ),
                    // Premium gradient button — deepNavy → navy gradient
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 640),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child)),
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _btnHovered = true),
                        onExit: (_) => setState(() => _btnHovered = false),
                        child: AnimatedScale(
                          scale: _btnHovered && !isDisabled ? 1.015 : 1.0,
                          duration: const Duration(milliseconds: 140),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: isDisabled
                                  ? null
                                  : const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Color(0xFF0D1B2A), Color(0xFF1E3A5F), Color(0xFF0D1B2A)],
                                    ),
                              color: isDisabled ? AppColors.deepNavy.withValues(alpha: 0.42) : null,
                              boxShadow: isDisabled
                                  ? []
                                  : _btnHovered
                                      ? [
                                          BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.24), blurRadius: 18, offset: const Offset(0, 8)),
                                          BoxShadow(color: AppColors.gold.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 0)),
                                        ]
                                      : [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.14), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: isDisabled ? null : widget.onSubmit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.transparent,
                                  disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
                                  shadowColor: Colors.transparent,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
                                ),
                                child: widget.isLoading
                                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Text(isLocked ? 'Try again in ${widget.lockLabel}' : 'Sign in'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account?", style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        TextButton(
                          onPressed: () => context.go(RouteConstants.webRegister),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), foregroundColor: AppColors.deepNavy),
                          child: const Text('Sign up', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Center(
                      child: Text('Having trouble? Contact your administrator.', style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary.withValues(alpha: 0.95))),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
