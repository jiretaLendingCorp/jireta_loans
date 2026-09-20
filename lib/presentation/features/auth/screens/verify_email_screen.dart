// lib/presentation/features/auth/screens/verify_email_screen.dart
//
// Huling hakbang ng lender pagkatapos ng "Fill In Information" modal: kailangang
// kumpirmahin ang email address na inilagay niya.
//
// LINK ang verification dito — HINDI OTP. Isang email ang ipinapadala ng server
// (via Resend) at ang pag-tap sa link na iyon ang nagpapatunay. Wala ditong
// code na ita-type; ang "Resend Email" button ang tanging aksyon.
//
// Awtomatikong sinusuri ng screen na ito (bawat ilang segundo) kung na-tap na
// ang link, kaya pagkumpirma sa email ay tuloy na ito sa dashboard — hindi na
// kailangang mag-navigate pabalik.
import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/security/secure_storage.dart';
import '../../lender/dashboard/providers/lender_dashboard_provider.dart';
import '../../lender/profile/providers/lender_profile_provider.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../../../shared/widgets/branded_loading_screen.dart';
import '../../../shared/widgets/dialogs/loading_dialog.dart';
import '../providers/auth_provider.dart';

/// Ang ipinapasa ng "Continue" ng Fill In Information papunta sa screen na ito.
class VerifyEmailArgs {
  const VerifyEmailArgs({required this.email, this.sendError});

  /// Ang email na pinadalhan ng verification link.
  final String email;

  /// Kung nabigo ang unang pagpapadala habang naglo-load ang Fill In
  /// Information, ang mensahe ng server (hal. hindi pa naka-configure ang email
  /// sending) — ipinapakita ito agad sa screen para hindi maghintay nang wala.
  final String? sendError;
}

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.args, this.token});

  final VerifyEmailArgs? args;

  /// Ang token na galing sa LINK ng email (`/verify-email?t=...`). Kapag meron
  /// nito, LINK mode ang screen: iko-confirm lang ang token — walang "Resend
  /// Email", walang pag-hintay ng link, at hindi kailangan ng naka-log in.
  final String? token;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  /// Gaano kadalas sinusuri kung na-tap na ang link sa email.
  static const _pollInterval = Duration(seconds: 5);

  /// Pagitan bago makapag-resend muli — tugma sa server-side cooldown
  /// (`RESEND_COOLDOWN_SECONDS` sa auth-email-verify). Sadyang maikli para
  /// agad na magamit ang "Resend Email" imbes na mukhang sira sa loob ng
  /// isang minuto.
  static const _resendCooldown = 15;

  Timer? _pollTimer;
  Timer? _cooldownTimer;

  String _email = '';
  String? _error;
  bool _resending = false;
  bool _verified = false;

  /// Habang tinitingnan ng "Verify Email" button kung na-tap na ang link.
  bool _verifying = false;
  int _cooldownLeft = 0;

  /// Link mode (galing sa email) o handoff mode (pagkatapos ng Continue).
  bool get _isLinkMode => (widget.token ?? '').isNotEmpty;

  /// Habang kinuku-kumpirma ang token sa LINK mode.
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _email = widget.args?.email ??
        ref.read(authStateProvider).user?.email ??
        '';
    _error = widget.args?.sendError;
    // LINK mode: ang token mula sa email ang iko-confirm — walang poll at
    // walang cooldown na kailangan.
    if (_isLinkMode) {
      _confirmToken(widget.token!);
      return;
    }
    // Hindi na inuumpisahan ang cooldown sa pagbukas: may naipadala nang link
    // habang naglo-load ang Fill In Information, pero HINDI dapat itong maging
    // dahilan para hindi mapindot ang Resend sa unang 60 segundo (iyon ang
    // dating naging "hindi gumagana ang resend"). Kapag masyadong mabilis ang
    // pindot, ang server ang magsasabi ng maikling hintay at makikita ito sa
    // error box sa ibaba.
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkVerified());
    // Unang tsek kaagad — baka na-tap na pala ang link bago pa dumating dito.
    _checkVerified();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() => _cooldownLeft = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldownLeft <= 1) {
        t.cancel();
        setState(() => _cooldownLeft = 0);
      } else {
        setState(() => _cooldownLeft -= 1);
      }
    });
  }

  /// Sinusuri kung kinumpirma na sa email ang link. Kapag oo, tuloy na sa
  /// dashboard — hindi na kailangang pindutin pa ang isang button.
  Future<void> _checkVerified() async {
    if (_verified) return;
    final ok = await ref.read(authProvider.notifier).isEmailVerified();
    if (!mounted || !ok || _verified) return;
    await _onVerifiedGoHome();
  }

  /// Ang "Verify Email" button: tsekin AGAD (hindi maghintay ng 5 segundo) kung
  /// na-tap na ang link sa email. Kapag oo → i-save ang Fill In Information at
  /// dumiretso sa home; kung hindi pa → malinaw na mensahe.
  Future<void> _verifyNow() async {
    if (_verifying || _verified) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    final ok = await ref.read(authProvider.notifier).isEmailVerified();
    if (!mounted) return;
    setState(() => _verifying = false);
    if (!ok) {
      setState(() => _error =
          'Hindi pa naka-verify ang email mo. Paki-tap ang link na ipinadala '
          'namin sa ${_email.isEmpty ? 'email address mo' : _email}, tapos '
          'pindutin muli ang Verify Email.');
      return;
    }
    await _onVerifiedGoHome();
  }

  /// Kapag na-verify na ang email: isinusulat muna ang Fill In Information ng
  /// lender, tapos naka-center na modal loading, tapos HOME (dashboard).
  Future<void> _onVerifiedGoHome() async {
    if (_verified) return;
    setState(() {
      _verified = true;
      _error = null;
    });
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    // ── Save sa oras ng verification (inutos ng user) ──────────────────
    // Hindi na hinihintay pang makarating sa dashboard ang update: isinusulat
    // dito ang pangalan / email na na-fill in, kaya siguradong naka-save ang
    // impormasyon bago ang paglipat. (Naisulat na rin ito noong "Continue";
    // idempotent lang ang pagsulat muli kaya walang masisira.)
    final saved = await _saveFilledInInformation();
    if (kDebugMode) {
      debugPrint('[VERIFY-EMAIL] na-verify na → save=$saved, papunta sa home');
    }
    if (!mounted) return;
    final hideLoading = showLoadingOverlay(context, text: 'Verifying…');
    await Future.delayed(const Duration(milliseconds: 1400));
    hideLoading();
    if (!mounted) return;
    context.go(RouteConstants.lenderDashboard);
  }

  /// Isinusulat (idempotent) ang "Fill In Information" ng lender — pangalan at
  /// email — sa oras na ma-verify ang email.
  ///
  /// ANG TOTOONG BUG NA NA-AYOS DITO: ang na-fill in na datos ay naka-save sa
  /// `SharedPreferences` sa ilalim ng **per-account na key** na gawa mula sa
  /// `authState.user?.id` (`lender_first_name_<userId>`). Kapag **`user` ay
  /// null** sa sandaling iyon (hal. na-restore lang na session na may token at
  /// role, o nag-lock ang MPIN) ay walang suffix na naisulat — samantalang dito
  /// sa Verify Your Email screen ay iba naman ang nakuha kaya HINDI ito natagpuan
  /// at TAHIMIK na umalis ang save ("hindi nag-sasave").
  ///
  /// Ngayon: (1) sinusubukan ang per-account na key, (2) ang walang-suffix na
  /// key, at (3) ang `SecureStorage` na userId para sa suffix — at NILALAGAY SA
  /// LOG ang bawat desisyon at ang resulta, para hindi na bulag sa susunod.
  /// Hindi rin tinatawag muli ang terms acceptance (naisulat na iyon noong
  /// Continue — doble lang ang record kung uulitin).
  Future<bool> _saveFilledInInformation() async {
    try {
      var userId = ref.read(authStateProvider).user?.id ?? '';
      if (userId.isEmpty) {
        // Fallback: ang estado ay maaaring wala pang `user` kahit may session.
        userId = await SecureStorage.getUserId() ?? '';
      }
      final suffix = userId.isEmpty ? '' : '_$userId';
      final prefs = await SharedPreferences.getInstance();

      /// Per-account na key muna; kung blangko, ang lumang walang-suffix na key
      /// (doon naisulat kapag walang `user` noong Continue).
      String pick(String key) {
        final withSuffix = (prefs.getString('$key$suffix') ?? '').trim();
        if (withSuffix.isNotEmpty || suffix.isEmpty) return withSuffix;
        return (prefs.getString(key) ?? '').trim();
      }

      final firstName = pick(AppConstants.lenderFirstNameKey);
      final middleName = pick(AppConstants.lenderMiddleNameKey);
      final lastName = pick(AppConstants.lenderLastNameKey);
      final suffixName = pick(AppConstants.lenderSuffixKey);
      var email = pick(AppConstants.lenderEmailKey);
      // Huling fallback: ang email ng account mismo (kung doon ipinadala ang
      // verification link, iyon na ang tamang email).
      if (email.isEmpty) {
        email = (ref.read(authStateProvider).user?.email ?? '').trim();
      }

      if (firstName.isEmpty && lastName.isEmpty && email.isEmpty) {
        if (kDebugMode) {
          debugPrint('[VERIFY-EMAIL] walang ma-save (suffix="$suffix"): '
              'walang first/last name at email sa prefs');
        }
        return false;
      }

      // ── (1) PANGALAN muna, hiwalay sa email ──────────────────────────
      // ANG TOTOONG DAHILAN NG "HINDI NAG-SAVE": ang email ay may
      // **uniqueness check sa server** — kung may ibang account nang gumagamit
      // nito (409 DUPLICATE), o tinanggihan ang format (400), ang BUONG tawag
      // ay nabibigo. Kapag isang tawag lang ang ginawa, ISASAMA ANG PANGALAN
      // SA PAGTANGGI — kaya kahit balido ang pangalan ay hindi ito nai-save sa
      // database. Ngayon, dalawa ang tawag: hindi na maaapektuhan ng problema
      // sa email ang pag-save ng pangalan.
      final namePayload = <String, dynamic>{
        if (firstName.isNotEmpty) 'first_name': firstName,
        if (middleName.isNotEmpty) 'middle_name': middleName,
        if (lastName.isNotEmpty) 'last_name': lastName,
        if (suffixName.isNotEmpty) 'suffix': suffixName,
      };
      var nameSaved = false;
      if (namePayload.isNotEmpty) {
        nameSaved = await ref
            .read(lenderProfileProvider.notifier)
            .updateProfile(namePayload);
      }

      // ── (2) EMAIL — hiwalay na tawag ────────────────────────────────────
      var emailSaved = false;
      if (email.isNotEmpty) {
        emailSaved = await ref
            .read(lenderProfileProvider.notifier)
            .updateProfile({'email': email});
      }

      if (kDebugMode) {
        debugPrint('[VERIFY-EMAIL] save fill-in name=$nameSaved '
            'email=$emailSaved payload=$namePayload email="$email" '
            'error=${ref.read(lenderProfileProvider).error}');
      }
      if (nameSaved || emailSaved) {
        // Ang Home ay nag-load na BAGO pa na-fill in ang info, kaya kung hindi
        // ito i-refresh ay luma/blanko pa ang pangalan doon kahit naka-save na.
        unawaited(ref.read(lenderDashboardProvider.notifier).refresh());
      }
      return nameSaved || emailSaved;
    } catch (e) {
      if (kDebugMode) debugPrint('[VERIFY-EMAIL] save fill-in error: $e');
      // Hindi hadlang sa pagpasok: naisulat na rin ang datos noong Continue.
      return false;
    }
  }

  Future<void> _resend() async {
    if (_resending || _cooldownLeft > 0) return;
    // Dati, TAHIMIK itong umaalis kapag walang email — kaya ang pakiramdam ay
    // "hindi gumagana ang Resend". Ngayon, may malinaw na mensahe.
    if (_email.isEmpty) {
      setState(() => _error =
          'Walang email address na maipapadala. Balik sa Fill In Information at ilagay ang email mo.');
      return;
    }
    setState(() {
      _resending = true;
      _error = null;
    });
    final error =
        await ref.read(authProvider.notifier).sendEmailVerification(
              email: _email,
            );
    if (!mounted) return;
    setState(() {
      _resending = false;
      _error = error;
    });
    if (error == null) {
      _startCooldown(_resendCooldown);
    }
  }

  /// Kinukumpirma ang token na galing sa link ng email.
  Future<void> _confirmToken(String token) async {
    setState(() {
      _confirming = true;
      _error = null;
    });
    final error =
        await ref.read(authProvider.notifier).confirmEmailVerification(
              token: token,
            );
    if (!mounted) return;
    setState(() {
      _confirming = false;
      _error = error;
      _verified = error == null;
    });
  }

  /// Ang pahina na binuksan ng LINK sa email (branded na domain, walang app
  /// chrome) — tagumpay o bigo, at hindi ito umaasa sa naka-log in na session.
  Widget _buildLinkMode() {
    if (_confirming) {
      return const BrandedLoadingScreen(message: 'Verifying your email…');
    }
    final ok = _verified;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: ok
                        ? AppColors.successLight
                        : AppColors.errorLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ok
                        ? Icons.mark_email_read_rounded
                        : Icons.error_outline_rounded,
                    size: 36,
                    color: ok ? AppColors.success : AppColors.error,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Jireta Loans',
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  ok ? 'Successfully Verified' : 'Verification Failed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: ok ? AppColors.success : AppColors.error,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  ok
                      ? 'Nakumpirma na ang email address mo. Bumalik ka na sa '
                          'Jireta Loans app at mag-login.'
                      : (_error ??
                          'Hindi ma-verify ang link na ito. Paki-request ng '
                              'bagong link mula sa app.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (!ok) ...[
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _confirming
                          ? null
                          : () => _confirmToken(widget.token!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.deepNavy,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Try Again',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLinkMode) return _buildLinkMode();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      // Hindi pa tapos ang verification — hindi dapat makalabas nang basta-basta
      // pabalik sa dashboard (kapareho ng MPIN setup). Ang "Resend Email" ang
      // paraan kapag hindi dumatíng ang mail.
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFFF7F8FA),
          body: SafeArea(
            // Ang "Resend Email" + "I've already verified" ay naka-dikit sa
            // IBABA ng screen (inutos ng user) — hindi na isang fixed na puwang
            // (na kailangang hulaan para sa bawat laki ng phone) ang nagtutulak
            // doon kundi isang `Spacer`. Kapag mas maikli ang screen kaysa sa
            // nilalaman, awtomatikong nagiging scrollable pa rin ito — kaya
            // hindi ito nag-o-overflow sa maliliit na device.
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                  // Walang "Jireta Loans / & Credit Corp 1966" na header sa
                  // itaas (inutos ng user na alisin) — ang email icon na lang
                  // ang nasa itaas, at ibinaba ito (inutos ng user).
                  const SizedBox(height: 150),

                  // ── Icon ──
                  // DARK BLUE ang email icon (inutos ng user) — hindi gold at
                  // hindi rin maliwanag na blue.
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: _verified
                          ? AppColors.successLight
                          : AppColors.infoLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _verified
                          ? Icons.mark_email_read_rounded
                          : Icons.mark_email_unread_rounded,
                      size: 36,
                      color: _verified
                          ? AppColors.success
                          : AppColors.lenderBlueLight,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Pamagat ──
                  Text(
                    _verified ? 'Successfully Verified' : 'Verify Your Email',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      color: AppColors.deepNavy,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Paliwanag ──
                  // Nakaalis lang ang "— tap the link to confirm, walang code
                  // na ita-type" na dulo (inutos ng user) — nananatili pa rin
                  // ang pangunahing paliwanag.
                  Text(
                    _verified
                        ? 'Salamat! Nakumpirma na ang email address mo.'
                        : 'Please check your email. We sent a verification '
                            'link to this address.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  // Bahagyang ibinaba ang email address (inutos ng user).
                  const SizedBox(height: 40),

                  // ── Ang email address ──
                  // Plain text na lang ito (inutos ng user): walang kahon,
                  // border, o background — dati kasi ay parang BUTTON ang
                  // dating nito — at walang "@" na icon sa unahan.
                  if (_email.isNotEmpty)
                    Text(
                      _email,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.deepNavy,
                      ),
                    ),

                  // ── Error (kung nabigo ang pagpapadala) ──
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.18)),
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
                                fontSize: 12.5,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Ito ang nagtutulak sa bloke (Resend Email + "I've already
                  // verified") sa PINAKAIBABA ng screen — kasingbaba ng
                  // pinapayagan ng screen (inutos ng user), anuman ang taas ng
                  // phone.
                  const Spacer(),

                  // ── RESEND EMAIL (primary) ──
                  // Ito na naman ang naka-primary na button (inutos ng user) —
                  // nagpapadala ito ng bagong verification link. Ang "Verify"
                  // na aksyon ay nasa text button sa ibaba, at may 5-segundong
                  // tahimik na pagsusuri pa rin pagkatapos i-tap ang link.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          (_resending || _cooldownLeft > 0 || _verified)
                              ? null
                              : _resend,
                      // DARK BLUE ang button (inutos ng user) — hindi gold at
                      // hindi rin maliwanag na blue.
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.lenderBlueLight,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.lenderBlueLight.withValues(alpha: 0.3),
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _resending
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Sending...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              _cooldownLeft > 0
                                  ? 'Resend Email in ${_cooldownLeft}s'
                                  : 'Resend Email',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                  // ── Ibinalik (inutos ng user) ──
                  // Ito ang nagsasagawa ng "verify" — tinitignan AGAD kung
                  // na-tap na ang link sa email.
                  TextButton(
                    onPressed:
                        (_verifying || _verified) ? null : _verifyNow,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.deepNavy,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                    ),
                    child: Text(
                      _verifying
                          ? 'Verifying...'
                          : "I've already verified. Check again",
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                      // Bahagyang itinaas mula sa pinakailalim (inutos ng user)
                      // — hindi ito dumidikit sa dulo ng screen.
                      const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
