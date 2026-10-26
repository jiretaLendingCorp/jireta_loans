// lib/presentation/features/auth/screens/otp_verify_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../auth_post_login.dart';
import '../providers/auth_provider.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../shared/widgets/layout/web_scaffold.dart' show kDesktopBreakpoint;
import 'mfa_verify_screen.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

/// Ang dinadaang argumento ng [RouteConstants.otpVerify] (`GoRouterState.extra`).
///
/// Ang `resetMpin` ay para sa "Reset MPIN" mula sa MPIN screen ng login page —
/// ipinapakita nito ang label na iyon dito sa OTP screen para malinaw sa user
/// na hindi ito ordinaryong login kundi pag-reset ng MPIN.
///
/// Ang reset flow ay may sariling URI ngayon
/// ([RouteConstants.resetMpinOtpVerify] — `/reset-mpin/verify-otp?s=<token>`),
/// kaya `resetMpin: true` dito ay fallback lang para sa lumang `/otp-verify`
/// na paglipat.
class OtpFlowArgs {
  const OtpFlowArgs({required this.phone, this.resetMpin = false});

  final String phone;
  final bool resetMpin;
}

class OtpVerifyScreen extends ConsumerStatefulWidget {
  final String phone;

  /// True kapag galing sa "Reset MPIN" — nagbabago ang titulo/label ng screen.
  final bool resetMpin;

  /// Opaque na token mula sa URL ng reset flow (`?s=…`). Kapag walang
  /// ipinasang [phone] (hal. na-refresh ang web page, kung saan nawawala ang
  /// `extra`), dito kinukuha ang numero — nasa secure storage ito, hindi sa
  /// address bar.
  final String? resetSessionToken;

  const OtpVerifyScreen({
    super.key,
    required this.phone,
    this.resetMpin = false,
    this.resetSessionToken,
  });

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

  /// Ang numerong ginagamit ng screen. Karaniwang galing sa [widget.phone]; sa
  /// reset flow ay maaaring ma-resolve pa lang mula sa secure storage kapag
  /// na-refresh ang page.
  String _phone = '';

  /// True habang hinahanap pa ang numero ng reset flow sa secure storage.
  bool _resolvingSession = false;
  // Wrong-OTP attempts for this verification session (reset when a new code
  // is requested). The server additionally locks the phone after 3 failures.
  int _attemptsUsed = 0;
  static const int _maxOtpAttempts = 3;
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
    _phone = widget.phone;
    if (_phone.isEmpty && widget.resetMpin) {
      if (widget.resetSessionToken == null ||
          widget.resetSessionToken!.isEmpty) {
        // Bukas na link na walang session: huwag hayaang mag-render ang OTP
        // screen na blangko ang numero.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(RouteConstants.mobileLogin);
        });
      } else {
        _resolvingSession = true;
        _resolveResetSession();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  /// Kinukuha ang numero ng reset flow mula sa secure storage (naka-key sa
  /// opaque na token ng URL). Kapag wala/iba ang token, ibinabalik sa login -
  /// hindi puwedeng mag-verify ng OTP na walang numero.
  Future<void> _resolveResetSession() async {
    final phone = await SecureStorage.readResetOtpPhone(widget.resetSessionToken);
    if (!mounted) return;
    if (phone == null || phone.isEmpty) {
      context.go(RouteConstants.mobileLogin);
      return;
    }
    setState(() {
      _phone = phone;
      _resolvingSession = false;
    });
    _focusNodes[0].requestFocus();
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
    // No toast on mobile — the inline lock countdown below the OTP boxes
    // already shows "Too many attempts / Try again in …".
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
    // Dismiss the keyboard right away so the loading state / next screen is
    // not covered by it.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    // Naka-authenticated na agad ang session kapag nagtagumpay ang OTP, kaya
    // puwede nang agawin ng router redirect ang screen (hal. staff →
    // dashboard). I-hold ito hanggang maipakita ang success dialog at
    // makapag-navigate ang screen mismo.
    ref.read(otpSuccessHandoffProvider.notifier).state = true;
    try {
      final ok = await ref.read(authProvider.notifier).verifyOtp(
            identifier: _phone,
            otp: otp,
            purpose: widget.resetMpin
                ? AppConstants.otpPurposeResetMpin
                : AppConstants.otpPurposeLogin,
          );
      if (!mounted) return;
      setState(() => _loading = false);
      if (ok) {
        // ── Reset authorization (reset flow lang) ────────────────────────────
        // Ang server ang gumawa ng single-use token na ito pagkatapos ng
        // purpose-matched na OTP. Ito ang kailangan ng `auth-mpin` para
        // palitan ang MPIN — hindi ang `resetMpin` flag ng app.
        if (widget.resetMpin) {
          final resetToken = ref.read(authProvider.notifier).mpinResetToken;
          if (resetToken == null || resetToken.isEmpty) {
            if (!mounted) return;
            setState(() => _error =
                'We could not verify the reset session. Please request a new code.');
            return;
          }
          await SecureStorage.saveMpinResetAuthorization(resetToken);
          final stored = await SecureStorage.getMpinResetAuthorization();
          if (!mounted) return;
          if (stored == null) {
            setState(() => _error =
                'We could not save the reset session. Please request a new code.');
            return;
          }
        }
        // ── Authenticator (TOTP) challenge MUNA, bago ang lahat ──────────────
        // Ang desisyon ay kinuha na ng [AuthNotifier] habang nag-e-verify ng OTP
        // (server ang unang pinagkukunan ng factor state, Supabase Auth ang
        // fallback), kaya dito ay binabasa na lang ito. Kapag may verified TOTP
        // factor ang account, hindi dapat maabot ang MPIN, ang dashboard, o
        // kahit ang "Reset MPIN" — sensitibo ang huli sa server at tinatanggihan
        // kapag `aal1` pa ang session.
        if (ref.read(authStateProvider).mfaRequired) {
          final loginMfa = ref.read(authProvider.notifier).loginMfa;
          await _showSuccessAndGo(
            RouteConstants.mfaVerify,
            extra: MfaVerifyArgs(
              factorId: loginMfa.factorId,
              phone: _phone,
              resetMpin: widget.resetMpin,
            ),
            title: 'OTP verified',
            message: 'Enter the 6-digit code from your authenticator app.',
          );
          return;
        }
        // ── "Reset MPIN": DERETSO sa paggawa ng bagong MPIN ─────────────────
        // Hindi na binubura dito ang lumang MPIN: ang bagong MPIN mismo ang
        // ipapalit ng `auth-mpin?fn=set` kapag may valid na reset token. Kung
        // mag-back ang user bago matapos, mananatili ang dating MPIN at hindi
        // siya maiiwang walang MPIN nang hindi sinasadya.
        if (widget.resetMpin) {
          // Isang beses lang dapat gamitin ang reset link/token na nasa URL.
          await SecureStorage.clearResetOtpSession();
          if (!mounted) return;
          await _showSuccessAndGo(
            RouteConstants.mpinSetup,
            title: 'OTP Verified',
            message: _phone.contains('@')
                ? 'Your email address is verified. Create your new MPIN now.'
                : 'Your mobile number is verified. Create your new MPIN now.',
            // Dito muna sa Verify OTP screen: 2 segundo ang dialog, tapos
            // deretso sa "Create Your MPIN".
            dialogDuration: const Duration(seconds: 2),
          );
          return;
        }
        // ── Susunod na screen pagkatapos ng OTP ─────────────────────────────
        // Rider / lender: palaging dumadaan muna sa MPIN (setup kung wala pa, o
        // "Enter MPIN" na may numerong ginamit); staff: dashboard ng role (o
        // force-password-change). Kapareho ito ng nangyayari sa pagbukas muli ng
        // app, kaya iisa ang takbo ng dalawang pagkakataon — iisang pinagmulan
        // na lang (`resolvePostAuthDestination`) dahil ginagamit din ito ng MFA
        // screen.
        // Ang MPIN screen ay may numero (hindi email) — iyon ang nakaimbak na
        // `phone_number` ng account, at iyon din ang ginagamit ng MPIN setup.
        final accountPhone =
            ref.read(authStateProvider).user?.phoneNumber ?? _phone;
        final destination =
            await resolvePostAuthDestination(ref, phone: accountPhone);
        if (!mounted) return;
        await _showSuccessAndGo(
          destination.location,
          extra: destination.extra,
        );
      } else {
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
        final err = ref.read(authProvider).error;
        var message = 'Wrong OTP code. Please check and try again.';
        if (err != null) {
          message = ref.read(authProvider.notifier).extractErrorMessage(err) ??
              message;
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
        // No toast — the inline error text below the OTP boxes is enough.
        // Show a proper validation message with the remaining attempts.
        _attemptsUsed++;
        final attemptsLeft = _maxOtpAttempts - _attemptsUsed;
        final attemptSuffix = attemptsLeft > 0
            ? ' Attempt $_attemptsUsed of $_maxOtpAttempts — '
                '$attemptsLeft attempt${attemptsLeft == 1 ? '' : 's'} left.'
            : ' Attempt $_attemptsUsed of $_maxOtpAttempts — '
                'no attempts left. Please request a new code.';
        setState(() => _error = '$message$attemptSuffix');
      }
    } finally {
      // Balik sa normal ang redirect pagkatapos ng dialog / navigation (o ng
      // bigong verification).
      ref.read(otpSuccessHandoffProvider.notifier).state = false;
    }
  }

  /// Ipinapakita ang "OTP Verified" success modal, TAPOS dinadala ang user
  /// sa [location].
  ///
  /// MAHALAGA ang pagkakasunod-sunod: ina-`await` muna ang modal bago
  /// mag-navigate. Kapag sabay silang tumakbo, pinapalitan ng go_router ang
  /// page sa ilalim ng modal (at nawawala ang confirmation) kada matagumpay
  /// na verification — kaya dating walang nakikitang "success" ang user
  /// pagkatapos mag-load ang Verify OTP.
  ///
  /// Ang router redirect ay naka-hold din habang nangyayari ito (tingnan ang
  /// [otpSuccessHandoffProvider]), kaya hindi maagaw ng "naka-authenticated →
  /// dashboard" na panuntunan ang screen bago pa lumitaw ang dialog.
  Future<void> _showSuccessAndGo(
    String location, {
    Object? extra,
    String title = 'OTP Verified Successfully',
    String message = 'Your OTP has been verified successfully.',
    Duration dialogDuration = const Duration(seconds: 2),
  }) async {
    await SuccessDialog.showAutoDismiss(
      context,
      title: title,
      message: message,
      duration: dialogDuration,
    );
    if (!mounted) return;
    context.go(location, extra: extra);
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _lockSecondsLeft > 0) return;
    final ok = await ref.read(authProvider.notifier).sendOtp(
          identifier: _phone,
          purpose: widget.resetMpin
              ? AppConstants.otpPurposeResetMpin
              : AppConstants.otpPurposeLogin,
        );
    if (!mounted) return;
    if (ok) {
      _startTimer();
      for (final c in _controllers) {
        c.clear();
      }
      setState(() {
        _error = null;
        _otp = '';
        _attemptsUsed = 0;
      });
      _focusNodes[0].requestFocus();
      // Totoong kalagayan ng SMS ayon sa server. Huwag sabihing "resent" na
      // parang naipadala na — maghihintay ang user ng code na wala pa.
      final notice = ref.read(authProvider.notifier).otpDeliveryNotice;
      if (notice != null) {
        context.showToast(notice);
      } else {
        context.showSnackBarAsToast(
          SnackBar(
            content: Text(
              _phone.contains('@')
                  ? 'Code resent to your email address. Please check your inbox.'
                  : 'Code resent to your mobile number by SMS.',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
    if (_resolvingSession) {
      // Sandali lang ito — hinahanap pa ang numero ng reset flow sa secure
      // storage bago ipakita ang card, para hindi lumitaw itong blangko.
      return const Scaffold(
        backgroundColor: Color(0xFFF7F8FA),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Email (Gmail) ang identifier? Hindi ito minamask gaya ng numero — mas
    // malinaw sa user kung saang email ipinadala ang code.
    final isEmail = _phone.contains('@');
    final maskedPhone = isEmail
        ? _phone
        : _phone.length == 11
        ? '${_phone.substring(0, 4)} \u2022\u2022\u2022\u2022 ${_phone.substring(7)}'
        : _phone;
    final canVerify = _otp.length == 6 && !_loading && _lockSecondsLeft == 0;
    final canResend = _secondsLeft == 0 && _lockSecondsLeft == 0 && !_loading;
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor:
            isDesktop ? const Color(0xFFFCFCFE) : const Color(0xFFF7F8FA),
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: _desktopFrame(Column(
                children: [
                  // Top bar: back button pinned top-left
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        _BackButton(
                          onTap: () => context.go(RouteConstants.mobileLogin),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  // Card: centered in the FULL remaining space — its position is
                  // locked and never moves, no matter where the title text sits.
                  // The title floats at a fixed offset above the card.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Track the card's rise: the card is centered in the
                        // remaining space, so it moves up by half the keyboard
                        // height. The title text moves up the same distance,
                        // keeping the gap constant and never getting covered.
                        final keyboardInset =
                            MediaQuery.of(context).viewInsets.bottom;
                        return Stack(
                          children: [
                            // Card centered in the full area (keyboard-aware)
                            Positioned.fill(
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Push the card down a bit while the
                                      // keyboard is open so it sits slightly
                                      // lower, closer to the keyboard.
                                      if (keyboardInset > 0)
                                        const SizedBox(height: 120),
                                      // ── Verify Code Card ──
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20),
                                        child: Container(
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(24),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.deepNavy
                                                    .withValues(alpha: 0.06),
                                                blurRadius: 24,
                                                offset: const Offset(0, 10),
                                              ),
                                            ],
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                22, 24, 22, 22),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                // Phone info (no box)
                                                Row(
                                                  children: [
                                                    Icon(
                                                        isEmail
                                                            ? Icons
                                                                .mail_outline_rounded
                                                            : Icons
                                                                .phone_rounded,
                                                        size: 14,
                                                        color:
                                                            AppColors.deepNavy),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const Text(
                                                            'Code sent to',
                                                            style: TextStyle(
                                                              fontSize: 10.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: AppColors
                                                                  .textTertiary,
                                                              letterSpacing:
                                                                  0.4,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 1),
                                                          Text(
                                                            maskedPhone,
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 13.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: AppColors
                                                                  .deepNavy,
                                                              letterSpacing:
                                                                  0.3,
                                                              fontFeatures: [
                                                                FontFeature
                                                                    .tabularFigures()
                                                              ],
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
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: List.generate(6,
                                                      (i) => _buildOtpBox(i)),
                                                ),

                                                // Inline error
                                                if (_error != null &&
                                                    _lockSecondsLeft == 0) ...[
                                                  const SizedBox(height: 14),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                          Icons
                                                              .error_outline_rounded,
                                                          size: 16,
                                                          color:
                                                              AppColors.error),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          _error!,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 12.5,
                                                            color:
                                                                AppColors.error,
                                                            fontWeight:
                                                                FontWeight.w600,
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
                                                      const Icon(
                                                          Icons.timer_rounded,
                                                          size: 15,
                                                          color:
                                                              AppColors.error),
                                                      const SizedBox(width: 10),
                                                      const Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              'Too many attempts',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: AppColors
                                                                    .error,
                                                              ),
                                                            ),
                                                            Text(
                                                              'Please wait before trying again',
                                                              style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: AppColors
                                                                      .error),
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
                                                          color:
                                                              AppColors.error,
                                                          fontFeatures: [
                                                            FontFeature
                                                                .tabularFigures()
                                                          ],
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
                                                              colors: [
                                                                AppColors
                                                                    .deepNavy,
                                                                Color(
                                                                    0xFF1A3658)
                                                              ],
                                                              begin: Alignment
                                                                  .topLeft,
                                                              end: Alignment
                                                                  .bottomRight,
                                                            )
                                                          : null,
                                                      color: canVerify
                                                          ? null
                                                          : const Color(
                                                              0xFFE8E8EE),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                      boxShadow: canVerify
                                                          ? [
                                                              BoxShadow(
                                                                color: AppColors
                                                                    .deepNavy
                                                                    .withValues(
                                                                        alpha:
                                                                            0.32),
                                                                blurRadius: 16,
                                                                offset:
                                                                    const Offset(
                                                                        0, 8),
                                                              ),
                                                            ]
                                                          : null,
                                                    ),
                                                    child: ElevatedButton(
                                                      onPressed: canVerify
                                                          ? _submit
                                                          : null,
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            Colors.transparent,
                                                        shadowColor:
                                                            Colors.transparent,
                                                        disabledBackgroundColor:
                                                            Colors.transparent,
                                                        disabledForegroundColor:
                                                            AppColors
                                                                .textTertiary
                                                                .withValues(
                                                                    alpha: 0.6),
                                                        foregroundColor:
                                                            Colors.white,
                                                        elevation: 0,
                                                        shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        14)),
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 20),
                                                      ),
                                                      child: _loading
                                                          ? const SizedBox(
                                                              height: 22,
                                                              width: 22,
                                                              child: CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2.4,
                                                                  color: Colors
                                                                      .white),
                                                            )
                                                          : Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Text(
                                                                  'Verify OTP',
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        15.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    letterSpacing:
                                                                        0.2,
                                                                    color: canVerify
                                                                        ? Colors
                                                                            .white
                                                                        : AppColors
                                                                            .textTertiary,
                                                                  ),
                                                                ),
                                                                if (canVerify) ...[
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
                                                                              alpha: 0.22),
                                                                      shape: BoxShape
                                                                          .circle,
                                                                    ),
                                                                    child: const Icon(
                                                                        Icons
                                                                            .arrow_forward_rounded,
                                                                        size:
                                                                            14,
                                                                        color: Colors
                                                                            .white),
                                                                  ),
                                                                ],
                                                              ],
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 14),

                                                // Divider with label
                                                const Row(
                                                  children: [
                                                    Expanded(
                                                        child: Divider(
                                                            color: Color(
                                                                0xFFE8E8EE),
                                                            thickness: 1)),
                                                    Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                              horizontal: 10),
                                                      child: Text(
                                                        'Having trouble?',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: AppColors
                                                              .textTertiary,
                                                          letterSpacing: 0.2,
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                        child: Divider(
                                                            color: Color(
                                                                0xFFE8E8EE),
                                                            thickness: 1)),
                                                  ],
                                                ),
                                                const SizedBox(height: 14),

                                                // Resend row
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text(
                                                      "Didn't receive code?",
                                                      style: TextStyle(
                                                          color: AppColors
                                                              .textSecondary,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w500),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    GestureDetector(
                                                      onTap: canResend
                                                          ? _resend
                                                          : null,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 16,
                                                                vertical: 9),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: canResend
                                                              ? AppColors
                                                                  .deepNavy
                                                              : const Color(
                                                                  0xFFF0F0F3),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(10),
                                                          border: Border.all(
                                                            color: canResend
                                                                ? AppColors
                                                                    .deepNavy
                                                                : const Color(
                                                                    0xFFE8E8EE),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              _lockSecondsLeft >
                                                                      0
                                                                  ? 'Locked $_lockLabel'
                                                                  : _secondsLeft >
                                                                          0
                                                                      ? 'Resend in ${_secondsLeft}s'
                                                                      : 'Resend code',
                                                              style: TextStyle(
                                                                fontSize: 12.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                letterSpacing:
                                                                    0.2,
                                                                color: canResend
                                                                    ? Colors
                                                                        .white
                                                                    : AppColors
                                                                        .textTertiary,
                                                                fontFeatures: const [
                                                                  FontFeature
                                                                      .tabularFigures()
                                                                ],
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
                            ),
                            // Title floating at a fixed offset — its height does
                            // not affect the card's centered position.
                            AnimatedPositioned(
                              // Pinned near the top (below the back button),
                              // matching the login page; rises out of the way
                              // when the keyboard opens (half its height, same
                              // as the card).
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              top: 32.0 - keyboardInset * 0.5,
                              left: 20,
                              right: 20,
                              child: Column(
                                children: [
                                  // Malinaw na ito ay pag-reset ng MPIN, hindi
                                  // ordinaryong login.
                                  if (widget.resetMpin) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppColors.gold
                                            .withValues(alpha: 0.16),
                                        borderRadius:
                                            BorderRadius.circular(99),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.lock_reset_rounded,
                                              size: 13,
                                              color: AppColors.deepNavy),
                                          SizedBox(width: 6),
                                          Text(
                                            'Reset MPIN',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                              color: AppColors.deepNavy,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  const Text(
                                    'Verify OTP',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.deepNavy,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.resetMpin
                                        ? 'We sent a 6-digit code to reset '
                                            'your MPIN.'
                                        : _phone.contains('@')
                                        ? 'We sent a 6-digit code to your '
                                            'email.'
                                        : 'We sent a 6-digit code to your '
                                            'phone.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // ── Footer (hidden while the keyboard is open) ──
                  if (MediaQuery.of(context).viewInsets.bottom == 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                      color: AppColors.textTertiary
                                          .withValues(alpha: 0.45),
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Text(
                                '\u00a9 1966  Jireta Loans & Credit Corp',
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
                                          .withValues(alpha: 0.45),
                                      shape: BoxShape.circle)),
                            ],
                          ),
                          SizedBox(
                              height:
                                  MediaQuery.of(context).padding.bottom + 4),
                        ],
                      ),
                    ),
                ],
              )),
            ),
          ),
        ),
      ),
    );
  }

  /// Desktop (≥ [kDesktopBreakpoint]) na balot ng OTP page: isang naka-center
  /// na makitid na column sa malawak na panel — kapareho ng login at MFA
  /// verification pages — imbes na isang card na nakaunat sa buong browser.
  /// Walang binabago sa mobile: doon ay buo pa rin ang lapad ng screen.
  Widget _desktopFrame(Widget child) {
    if (MediaQuery.sizeOf(context).width < kDesktopBreakpoint) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: child,
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
      borderColor = const Color(0xFFE3E5EB);
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
      borderColor = const Color(0xFFE3E5EB);
      borderWidth = 1.2;
      fillColor = const Color(0xFFF2F3F7);
    }

    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(
            left: index == 0 ? 0 : 5, right: index == 5 ? 0 : 5),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.backspace) {
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
            height: 48,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(12),
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
                  // Naka-none na ang borders dahil ang AnimatedContainer na ang
                  // nagda-draw ng box. Kailangang naka-off din ang fill —
                  // kung hindi, hinihiram niya ang filled:true + white fill
                  // mula sa global InputDecorationTheme kaya nagkakaroon ng
                  // "box sa loob ng box".
                  filled: false,
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE3E5EB)),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.deepNavy, size: 16),
        ),
      ),
    );
  }
}
