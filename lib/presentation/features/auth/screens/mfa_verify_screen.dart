// lib/presentation/features/auth/screens/mfa_verify_screen.dart
//
// ── \"Verify it's you\" — authenticator (TOTP) challenge ──────────────────────
//
// Ang screen na ito ang humihingi ng 6-digit na code mula sa Google
// Authenticator pagkatapos ng phone-OTP login o email/password login, KAPAG may
// verified TOTP factor ang account (kasama ang employee role).
//
// Paano ito hindi nalalampasan:
//   * ang router redirect (`mfaRedirect`) ay hindi pumapayag na mabuksan ang
//     alinmang protected na pahina habang may nakabinbing challenge — pati
//     ang deep link;
//   * ang tunay na hangganan ay server-side: ang tokens na hawak ng app bago
//     ang `mfa.verify` ay `aal1` pa, at ang mga sensitibong Edge Function ay
//     tumatanggi sa `aal1` kapag may naka-enroll na factor (`_shared/mfa.ts`).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/security/mfa_service.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/logger.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../../../shared/widgets/layout/web_scaffold.dart' show kDesktopBreakpoint;
import '../auth_post_login.dart';

/// Ang `GoRouterState.extra` ng `/mfa-verify`.
///
/// Ang [factorId] ay ang identifier ng factor sa GoTrue (hindi ang TOTP
/// secret). Kapag `null`, ang screen mismo ang kukuha ng factor list mula sa
/// Supabase Auth.
class MfaVerifyArgs {
  const MfaVerifyArgs({
    this.factorId,
    this.phone,
    this.resetMpin = false,
  });

  final String? factorId;

  /// Ang numerong ginamit sa login — ipinapasa sa MPIN screen sa dulo ng flow.
  final String? phone;

  /// `true` kapag \"Reset MPIN\" ang pinanggalingang flow: pagkatapos ng MFA
  /// ay binubura ang lumang MPIN at sa create screen dadalhin ang user.
  final bool resetMpin;
}

class MfaVerifyScreen extends ConsumerStatefulWidget {
  const MfaVerifyScreen({super.key, this.args});

  final MfaVerifyArgs? args;

  @override
  ConsumerState<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends ConsumerState<MfaVerifyScreen> {
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  /// Hanggang 5 maling code bago hilingin ang muling pag-login (ang GoTrue ay
  /// may sarili ring rate limit).
  static const int _maxAttempts = MfaService.maxVerificationAttempts;

  String? _factorId;
  bool _preparing = true;
  bool _submitting = false;
  String? _error;
  int _attempts = 0;

  /// Countdown kapag nag-„rate limit\" ang GoTrue (429) — habang tumatakbo ito
  /// ay hindi pinapayagan ang pag-submit.
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _factorId = widget.args?.factorId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
    if (_factorId == null) {
      _resolveFactor();
    } else {
      _preparing = false;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Kinukuha ang factor id mula sa Supabase Auth (GET /user) kapag hindi ito
  /// ipinasa ng OTP screen. Kapag wala nang verified factor ang account (hal.
  /// na-disable ito sa ibang device), hindi na pinipigil ang user — walang MFA
  /// na ipinag-uutos kahit sa server.
  Future<void> _resolveFactor() async {
    try {
      final status = await ref.read(mfaServiceProvider).status();
      if (!mounted) return;
      if (!status.enrolled || status.factorId == null) {
        await ref.read(authStateProvider.notifier).clearMfaRequired();
        if (!mounted) return;
        await _continueAfterVerification();
        return;
      }
      setState(() {
        _factorId = status.factorId;
        _preparing = false;
      });
    } catch (e) {
      AppLogger.w('[MFA] hindi makuha ang factor list: $e');
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = e is MfaFailure
            ? e.message
            : const MfaFailure(MfaFailureKind.network).message;
      });
    }
  }

  void _onCodeChanged(String value) {
    if (_error != null) setState(() => _error = null);
    if (value.length == 6 && !_submitting) {
      _submit();
    }
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    final factorId = _factorId;
    if (_cooldownSeconds > 0 || _submitting) return;
    if (factorId == null) {
      await _resolveFactor();
      return;
    }
    if (!MfaService.isValidCode(code)) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator '
          'app.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // GoTrue ang nag-e-verify — at ang tagumpay dito ang nagpapataas ng
      // session sa `aal2` (bagong access + refresh token). Ang app ay hindi
      // nagtatakda ng sariling \"verified\" flag.
      await ref
          .read(mfaServiceProvider)
          .verifyLogin(factorId: factorId, code: code);
      if (!mounted) return;
      await ref.read(authStateProvider.notifier).clearMfaRequired();
      if (!mounted) return;
      await _continueAfterVerification();
    } on MfaFailure catch (e) {
      if (!mounted) return;
      _handleFailure(e);
    } catch (e) {
      AppLogger.w('[MFA] verify failed: $e');
      if (!mounted) return;
      _handleFailure(mfaFailureFrom(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleFailure(MfaFailure failure) {
    _codeCtrl.clear();
    setState(() {
      _attempts++;
      _error = failure.kind == MfaFailureKind.notEnrolled
          // Na-disable na ang factor: wala nang ipinag-uutos na MFA.
          ? 'Authenticator verification is no longer set up for this account.'
          : failure.message;
    });
    if (failure.kind == MfaFailureKind.tooManyAttempts) {
      _startCooldown(failure.retryAfterSeconds ?? 60);
    }
    if (failure.kind == MfaFailureKind.notEnrolled) {
      // Hindi na kailangan ang gate — hayaan nang magpatuloy (ang server ang
      // huling salita sa mga sensitibong aksyon).
      unawaited(_releaseGateAndContinue());
      return;
    }
    if (_attempts >= _maxAttempts) {
      setState(() {
        _error = 'Too many incorrect codes. Please sign in again to get a new '
            'code challenge.';
      });
    }
    if (mounted) _codeFocus.requestFocus();
  }

  Future<void> _releaseGateAndContinue() async {
    await ref.read(authStateProvider.notifier).clearMfaRequired();
    if (!mounted) return;
    await _continueAfterVerification();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        t.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds--);
      }
    });
  }

  /// Pagkatapos ng TAGUMPAY na MFA — kaparehong takbo ng OTP screen
  /// ([resolvePostAuthDestination]): rider / lender ay dumadaan pa sa MPIN
  /// (setup o \"Enter MPIN\"), staff ay sa dashboard.
  Future<void> _continueAfterVerification() async {
    if (widget.args?.resetMpin == true) {
      // Naka-save na ang server-issued reset authorization bago pa dumating
      // dito ang user (OTP screen). Dito lang siya dadalhin sa paggawa ng
      // bagong MPIN; ang server pa rin ang magpapatunay ng token.
      context.go(RouteConstants.mpinSetup);
      return;
    }
    final destination =
        await resolvePostAuthDestination(ref, phone: widget.args?.phone);
    if (!mounted) return;
    context.go(destination.location, extra: destination.extra);
  }

  /// Staff (employee / head manager) ang pumapasok sa web email/password
  /// login; ang rider/lender ay sa mobile OTP login. Gamit ito para tama ang
  /// "use another account" na landas at label.
  bool get _isStaff {
    final role = ref.read(authStateProvider).role;
    return role == AppConstants.roleEmployee ||
        role == AppConstants.roleHeadManager;
  }

  /// Hard logout: binubura ang tokens (kasama ang pending marker) at ang
  /// Supabase session — kaya hindi na maipit ang user sa pagitan ng MFA screen
  /// at MPIN lock. Kailangan ng bagong login + authenticator code para
  /// makapasok muli.
  Future<void> _signOut() async {
    // Basahin bago i-clear ang auth state — mawawala ang role pagkatapos ng
    // logout, kaya hindi na matukoy kung saan ang login page.
    final staff = _isStaff;
    try {
      await SecureStorage.clearAll();
      await ref.read(authStateProvider.notifier).logout();
    } catch (e) {
      AppLogger.w('[MFA] sign out failed: $e');
    }
    if (!mounted) return;
    context.go(staff ? RouteConstants.webLogin : RouteConstants.mobileLogin);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    final canSubmit =
        !_submitting && !_preparing && _cooldownSeconds == 0 && _factorId != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor:
            isDesktop ? const Color(0xFFFCFCFE) : const Color(0xFFF7F8FA),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCard(canSubmit),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _submitting ? null : _signOut,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: Text(
                        _isStaff ? 'Use another account' : 'Use another number',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.deepNavy,
                        disabledForegroundColor: AppColors.textTertiary,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Lost access to your authenticator app? Contact Jireta '
                        'support or your head manager to reset 2FA after '
                        'verifying your identity.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(bool canSubmit) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Icon chip: nasa KALIWA lang — hindi naka-stretch sa buong
          // lapad ng card (dati'y nagiging kulay-abo na bar ang chip). ──
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.deepNavy.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.verified_user_outlined,
                  size: 26, color: AppColors.deepNavy),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "Verify it's you",
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.deepNavy,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Open Google Authenticator (or any authenticator app), then enter '
            'the 6-digit code for Jireta Loans.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 22),
          // ── 6 segmented na kahon (tulad ng OTP screen) — mas malinaw na
          // 6-digit code ang hinihingi kaysa sa isang malaking text field. ──
          _MfaCodeInput(
            controller: _codeCtrl,
            focusNode: _codeFocus,
            enabled: !_preparing && _cooldownSeconds == 0,
            hasError: _error != null,
            onChanged: _onCodeChanged,
            onSubmitted: _submit,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: canSubmit
                    ? const LinearGradient(
                        colors: [AppColors.deepNavy, Color(0xFF1A3658)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: canSubmit ? null : const Color(0xFFE8E8EE),
                borderRadius: BorderRadius.circular(14),
                boxShadow: canSubmit
                    ? [
                        BoxShadow(
                          color: AppColors.deepNavy.withValues(alpha: 0.28),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: ElevatedButton(
                onPressed: canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  disabledForegroundColor:
                      AppColors.textTertiary.withValues(alpha: 0.6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _preparing || _submitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          // Puti lang kapag aktibo ang navy na CTA; kung hindi,
                          // hindi ito makikita sa kulay-abong disabled na fondo.
                          color: canSubmit
                              ? Colors.white
                              : AppColors.textTertiary,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _cooldownSeconds > 0
                                ? 'Wait ${_cooldownSeconds}s'
                                : _attempts >= _maxAttempts
                                    ? 'Sign in again'
                                    : 'Verify code',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: canSubmit
                                  ? Colors.white
                                  : AppColors.textTertiary,
                            ),
                          ),
                          if (canSubmit) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_forward_rounded,
                                  size: 14, color: Colors.white),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
          if (_attempts >= _maxAttempts && _cooldownSeconds == 0) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _submitting ? null : _signOut,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _isStaff
                    ? 'Sign out and use another account'
                    : 'Sign out and use another number',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Anim na segmented na kahon para sa 6-digit authenticator code.
///
/// Nasa ILALIM ang tunay na [TextField] (hindi nakikita, transparent) kaya
/// pareho pa rin ang pag-type, backspace at paste — ang mga kahon lang ang
/// ipinapakita, tulad ng OTP screen ng app.
class _MfaCodeInput extends StatefulWidget {
  const _MfaCodeInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
  });

  /// Haba ng authenticator code.
  static const int length = 6;

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  State<_MfaCodeInput> createState() => _MfaCodeInputState();
}

class _MfaCodeInputState extends State<_MfaCodeInput> {
  /// Isang listenable para parehong nagre-render muli kapag nagbago ang code
  /// at kapag nagbago ang focus (para sa highlight ng susunod na kahon).
  late final Listenable _repaint =
      Listenable.merge([widget.controller, widget.focusNode]);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _repaint,
      builder: (context, _) {
        final code = widget.controller.text;
        final focused = widget.focusNode.hasFocus;
        return Stack(
          children: [
            // Tunay na input — hindi nakikita pero ito ang tumatanggap ng
            // keyboard, paste at backspace.
            Positioned.fill(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: _MfaCodeInput.length,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                showCursor: false,
                enableInteractiveSelection: false,
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                cursorWidth: 0,
                // Lahat ng border state ay tahasang `InputBorder.none` at
                // `filled: false` — kung hindi, ipinipinta pa rin ng global
                // `InputDecorationTheme` ang enabled/focused border at ang
                // puting fill nito, kaya may linya/box na lumalabas sa ilalim
                // ng mga kahon (doble ang box).
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: widget.onChanged,
                onSubmitted: (_) => widget.onSubmitted(),
              ),
            ),
            // Mga kahon sa ibabaw — i-tap ang kahit alin para mag-focus at
            // maituon ang cursor sa dulo (hindi sa gitna ng code).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!widget.enabled) return;
                widget.focusNode.requestFocus();
                widget.controller.selection = TextSelection.collapsed(
                  offset: widget.controller.text.length,
                );
              },
              child: Row(
                children: [
                  for (var i = 0; i < _MfaCodeInput.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: i == 0 ? 0 : 5,
                          right: i == _MfaCodeInput.length - 1 ? 0 : 5,
                        ),
                        child: _box(i, code, focused),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _box(int index, String code, bool focused) {
    final char = index < code.length ? code[index] : '';
    final filled = char.isNotEmpty;
    final active = widget.enabled && focused && index == code.length;

    Color borderColor;
    double borderWidth;
    Color fillColor;
    if (widget.hasError) {
      borderColor = AppColors.error;
      borderWidth = 1.6;
      fillColor = AppColors.errorLight;
    } else if (!widget.enabled) {
      borderColor = const Color(0xFFE3E5EB);
      borderWidth = 1.1;
      fillColor = const Color(0xFFF0F0F3);
    } else if (active) {
      borderColor = AppColors.deepNavy;
      borderWidth = 1.8;
      fillColor = Colors.white;
    } else if (filled) {
      borderColor = AppColors.deepNavy.withValues(alpha: 0.18);
      borderWidth = 1.4;
      fillColor = Colors.white;
    } else {
      borderColor = const Color(0xFFE3E5EB);
      borderWidth = 1.2;
      fillColor = const Color(0xFFF2F3F7);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.deepNavy.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Text(
        char,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: widget.enabled
              ? AppColors.deepNavy
              : AppColors.textTertiary.withValues(alpha: 0.6),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
