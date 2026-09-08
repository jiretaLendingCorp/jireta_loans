// lib/presentation/features/auth/screens/web_login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../../../shared/providers/connectivity_provider.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/offline_toast.dart';
import '../providers/auth_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

/// Centered web login — single light panel with the login form centered.
/// No split-screen brand panel.
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

  @override
  void initState() {
    super.initState();
    _pageCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _cardFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _pageCtrl,
          curve: const Interval(0.18, 0.82, curve: Curves.easeOutCubic)),
    );
    _cardSlide =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(
          parent: _pageCtrl,
          curve: const Interval(0.18, 0.82, curve: Curves.easeOutCubic)),
    );
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
      // Clear both fields so the user re-types them on the next attempt.
      _emailCtrl.clear();
      _passCtrl.clear();
      final err = ref.read(authProvider).error;
      final lockSecs = notifier.extractOtpLockoutSeconds(err ?? '');
      if (lockSecs != null && lockSecs > 0) {
        _startLockCountdown(lockSecs);
        return;
      }
      _showError(
          notifier.extractErrorMessage(err ?? 'Error') ?? 'Login failed.');
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

  void _showSecurityNotice(String message) {
    // Product spec: the "Session Ended" modal sticks for ~3 seconds, then the
    // login page is revealed. OK remains as an early-dismiss option.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var dismissed = false;
        Future.delayed(const Duration(seconds: 3), () {
          if (!dismissed && ctx.mounted) Navigator.of(ctx).pop();
        });
        return AlertDialog(
          icon: const Icon(Icons.security_rounded,
              color: AppColors.error, size: 34),
          title: const Text('Session Ended',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: Text(message, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () {
                dismissed = true;
                Navigator.of(ctx).pop();
              },
              child: const Text('OK',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
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
    // Single-active-session: if the previous session was revoked by a newer
    // login on another device, explain why the user was signed out.
    ref.listen<String?>(
      authStateProvider.select((s) => s.securityMessage),
      (previous, next) {
        if (next == null || next.trim().isEmpty) return;
        ref.read(authStateProvider.notifier).clearSecurityMessage();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showSecurityNotice(next);
        });
      },
    );
    final isLoading = ref.watch(authProvider).isLoading;
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;

    final loginCard = FadeTransition(
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
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Stack(
        children: [
          // Centered login form — no blue split panel.
          _FormPanel(child: loginCard),
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
// Form panel — light surface that hosts the login card
// ─────────────────────────────────────────────────────────────────────────────

class _FormPanel extends StatelessWidget {
  final Widget child;
  const _FormPanel({required this.child});

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
          // faint gold glow echoing the brand panel
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
          Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
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
// Premium login card — email/password form with animated interactions
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
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Eyebrow pill ──
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBF6EA),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: AppColors.gold, shape: BoxShape.circle)),
                    const SizedBox(width: 7),
                    const Text(
                      'STAFF PORTAL',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: AppColors.deepNavy),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Login',
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
                'Sign in to continue to your workspace.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.6,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w400),
              ),
            ),
            const SizedBox(height: 30),
            // ── Email ──
            const _FieldLabel('Email Address'),
            const SizedBox(height: 8),
            MouseRegion(
              onEnter: (_) => setState(() => _emailHovered = true),
              onExit: (_) => setState(() => _emailHovered = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: widget.emailFocus.hasFocus || _emailHovered
                      ? [
                          BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.14),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ]
                      : [],
                ),
                child: TextFormField(
                  controller: widget.emailCtrl,
                  focusNode: widget.emailFocus,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  maxLength: 254,
                  readOnly: isLocked,
                  onTap: () => setState(() {}),
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    hintStyle: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textTertiary.withValues(alpha: 0.75)),
                    prefixIcon: Icon(Icons.mail_outlined,
                        size: 18,
                        color: widget.emailFocus.hasFocus
                            ? AppColors.deepNavy
                            : AppColors.textTertiary),
                    counterText: '',
                    filled: true,
                    fillColor: widget.emailFocus.hasFocus
                        ? Colors.white
                        : const Color(0xFFF8F9FC),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 15),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: _emailHovered
                              ? const Color(0xFFCBD2DE)
                              : const Color(0xFFE4E7EE)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.deepNavy, width: 1.4),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.error),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.error, width: 1.4),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    if (!AppValidators.isValidEmail(v))
                      return 'Enter a valid email';
                    return null;
                  },
                  onFieldSubmitted: (_) => widget.passFocus.requestFocus(),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // ── Password ──
            const _FieldLabel('Password'),
            const SizedBox(height: 8),
            MouseRegion(
              onEnter: (_) => setState(() => _passHovered = true),
              onExit: (_) => setState(() => _passHovered = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: widget.passFocus.hasFocus || _passHovered
                      ? [
                          BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.14),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ]
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
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    hintStyle: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textTertiary.withValues(alpha: 0.75)),
                    prefixIcon: Icon(Icons.lock_outline_rounded,
                        size: 18,
                        color: widget.passFocus.hasFocus
                            ? AppColors.deepNavy
                            : AppColors.textTertiary),
                    counterText: '',
                    filled: true,
                    fillColor: widget.passFocus.hasFocus
                        ? Colors.white
                        : const Color(0xFFF8F9FC),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 15),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: _passHovered
                              ? const Color(0xFFCBD2DE)
                              : const Color(0xFFE4E7EE)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.deepNavy, width: 1.4),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.error),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.error, width: 1.4),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                          widget.obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: AppColors.textSecondary),
                      onPressed: widget.onToggleObscure,
                      tooltip:
                          widget.obscure ? 'Show password' : 'Hide password',
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
            // ── Forgot password ──
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.go(RouteConstants.forgotPassword),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  foregroundColor: AppColors.deepNavy,
                  shape: const RoundedRectangleBorder(),
                ),
                child: const Text('Forgot password?',
                    style:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
            // ── Lock countdown banner ──
            if (isLocked) ...[
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.18)),
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
                      child: Text(
                        'Too many attempts',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error),
                      ),
                    ),
                    Text(
                      widget.lockLabel,
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
              const SizedBox(height: 12),
            ] else
              const SizedBox(height: 12),
            // ── Premium gradient CTA ──
            MouseRegion(
              onEnter: (_) => setState(() => _btnHovered = true),
              onExit: (_) => setState(() => _btnHovered = false),
              child: AnimatedScale(
                scale: _btnHovered && !isDisabled ? 1.01 : 1.0,
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
                              Color(0xFF0D1B2A)
                            ],
                          ),
                    color: isDisabled
                        ? AppColors.deepNavy.withValues(alpha: 0.42)
                        : null,
                    boxShadow: isDisabled
                        ? []
                        : _btnHovered
                            ? [
                                BoxShadow(
                                    color: AppColors.deepNavy
                                        .withValues(alpha: 0.28),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10)),
                                BoxShadow(
                                    color:
                                        AppColors.gold.withValues(alpha: 0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 0)),
                              ]
                            : [
                                BoxShadow(
                                    color: AppColors.deepNavy
                                        .withValues(alpha: 0.16),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6))
                              ],
                  ),
                  child: ElevatedButton(
                    onPressed: isDisabled ? null : widget.onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.transparent,
                      disabledForegroundColor:
                          Colors.white.withValues(alpha: 0.9),
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
                    child: widget.isLoading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(isLocked
                            ? 'Try again in ${widget.lockLabel}'
                            : 'Login'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // ── Register row ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Don't have an account?",
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => context.go(RouteConstants.webRegister),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    foregroundColor: AppColors.deepNavy,
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: const Text('Register',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
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
