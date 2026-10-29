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
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _submitting ? null : _signOut,
                      child: Text(
                        _isStaff ? 'Use another account' : 'Use another number',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Lost access to your authenticator app? Contact Jireta '
                      'support or your head manager to reset 2FA after '
                      'verifying your identity.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.textSecondary,
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.lenderBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.verified_user_outlined,
                size: 24, color: AppColors.lenderBlue),
          ),
          const SizedBox(height: 14),
          const Text(
            "Verify it's you",
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Open Google Authenticator (or any authenticator app), then enter '
            'the 6-digit code for Jireta Loans.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _codeCtrl,
            focusNode: _codeFocus,
            enabled: !_preparing && _cooldownSeconds == 0,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 8,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: const TextStyle(letterSpacing: 8, fontSize: 22),
              filled: true,
              fillColor: const Color(0xFFF7F8FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            onChanged: _onCodeChanged,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline,
                    size: 16, color: AppColors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.lenderBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _preparing || _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _cooldownSeconds > 0
                          ? 'Wait ${_cooldownSeconds}s'
                          : _attempts >= _maxAttempts
                              ? 'Sign in again'
                              : 'Verify code',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
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
