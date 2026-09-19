// lib/presentation/features/auth/screens/forgot_password_screen.dart
// Forgot Password -> Enter email -> send 6-digit OTP -> Reset Password screen.
// Styling mirrors the web login / register card so the auth flow looks uniform.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  bool _emailHovered = false;
  bool _submitting = false;
  int _lockSecondsLeft = 0;
  Timer? _lockTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _emailFocus.dispose();
    _lockTimer?.cancel();
    super.dispose();
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

  Future<void> _submit() async {
    if (_submitting || _lockSecondsLeft > 0) return;
    if (!_formKey.currentState!.validate()) return;
    final email = AppValidators.normalizeEmail(_emailCtrl.text);
    final notifier = ref.read(authProvider.notifier);
    setState(() => _submitting = true);
    final ok = await notifier.forgotPassword(email: email);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      // OTP flow: go directly to Reset Password (OTP + New Password).
      // SECURITY: the URL carries the opaque reset token (64 hex chars), never
      // the email — query strings leak into browser history, access logs,
      // analytics and the Referer header of third-party requests.
      final token = notifier.resetToken;
      context.go(
        token == null || token.isEmpty
            ? RouteConstants.resetPassword
            : '${RouteConstants.resetPassword}?t=$token',
        // The address rides along in memory only (never in the URL) so the
        // reset screen can show "code sent to <email>". A reload drops it —
        // the URL token still authorises the flow, the email is only needed to
        // resend.
        extra: email,
      );
      return;
    }
    final err = ref.read(authProvider).error;
    final msg = notifier.extractErrorMessage(err ?? 'Error') ??
        'Failed to send reset code. Please try again.';
    final lockSecs = notifier.extractOtpLockoutSeconds(err ?? '');
    if (lockSecs != null && lockSecs > 0) _startLockCountdown(lockSecs);
    context.showSnackBarAsToast(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  InputDecoration _input({String? hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          fontSize: 13.5,
          color: AppColors.textTertiary.withValues(alpha: 0.75)),
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 18, color: AppColors.textTertiary),
      counterText: '',
      errorMaxLines: 3,
      errorStyle:
          const TextStyle(fontSize: 12, height: 1.35, color: AppColors.error),
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

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading || _submitting;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: _ForgotPanel(
        onBack: () => context.go(RouteConstants.webLogin),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(
                child: Text(
                  'Forgot Password?',
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
                  "Enter the email linked to your account and we'll send you a 6-digit verification code.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.6,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const _FieldLabel('Email Address'),
              const SizedBox(height: 8),
              MouseRegion(
                onEnter: (_) => setState(() => _emailHovered = true),
                onExit: (_) => setState(() => _emailHovered = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _emailFocus.hasFocus || _emailHovered
                        ? [
                            BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.14),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: TextFormField(
                    controller: _emailCtrl,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.done,
                    maxLength: 254,
                    readOnly: _lockSecondsLeft > 0,
                    onTap: () => setState(() {}),
                    onFieldSubmitted: (_) => _submit(),
                    style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500),
                    decoration: _input(
                        hint: 'you@example.com', icon: Icons.mail_outlined),
                    validator: AppValidators.email,
                  ),
                ),
              ),
              if (_lockSecondsLeft > 0) ...[
                const SizedBox(height: 16),
                _LockBanner(secondsLeft: _lockSecondsLeft),
              ] else
                const SizedBox(height: 12),
              // The OTP is short-lived — tell the user up front so the resend
              // step on the next screen is not a surprise.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.schedule_rounded,
                        size: 15, color: AppColors.textTertiary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The code expires in 1 minute. You can resend a new code from the next screen.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textSecondary.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _PrimaryButton(
                label: 'Send Code',
                loading: isLoading,
                onPressed: (isLoading || _lockSecondsLeft > 0) ? null : _submit,
              ),
              const SizedBox(height: 14),
              _LinkRow(
                prompt: 'Remember your password?',
                action: 'Login',
                onPressed: () => context.go(RouteConstants.webLogin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel — light gradient surface hosting the centered form
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotPanel extends StatelessWidget {
  final Widget child;
  final VoidCallback onBack;
  const _ForgotPanel({required this.child, required this.onBack});

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
          // faint gold glow echoing the login / register panels
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
                    tooltip: 'Back to login',
                    icon: const Icon(Icons.arrow_back,
                        size: 20, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Builder(builder: (context) {
              // Mobile: mas maliit na padding para hindi masikip ang card.
              final narrow = MediaQuery.sizeOf(context).width < 600;
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: narrow ? 16 : 32,
                  vertical: narrow ? 28 : 72,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: child,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared pieces (lifted from the login / register screens)
// ─────────────────────────────────────────────────────────────────────────────

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

class _LockBanner extends StatelessWidget {
  final int secondsLeft;
  const _LockBanner({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
                color: AppColors.error, shape: BoxShape.circle),
            child:
                const Icon(Icons.timer_rounded, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Too many requests',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error),
            ),
          ),
          Text(
            '$secondsLeft s',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.error,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
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
            color:
                isDisabled ? AppColors.deepNavy.withValues(alpha: 0.42) : null,
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
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1),
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
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
