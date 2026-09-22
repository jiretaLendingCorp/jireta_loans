// lib/presentation/features/auth/screens/mobile_login_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/route_constants.dart';
import '../../../../core/security/mpin_login_gate.dart';
import '../../../../core/security/mpin_service.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../../../shared/providers/connectivity_provider.dart';
import '../../../shared/widgets/dialogs/loading_dialog.dart';
import '../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../shared/widgets/branded_loading_screen.dart';
import '../../../shared/widgets/legal_links.dart';
import '../../../shared/widgets/offline_toast.dart';
import '../../../shared/widgets/security/mpin_keypad.dart';
import '../providers/auth_provider.dart';
import 'otp_verify_screen.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class MobileLoginScreen extends ConsumerStatefulWidget {
  const MobileLoginScreen({super.key, this.handoff});

  /// Alam na ang sagot kung MPIN ba ang hihingin — galing ito sa OTP verify o
  /// sa MPIN setup, na parehong may numerong hawak na at alam kung may naka-set
  /// nang MPIN.
  ///
  /// BAKIT: kung wala ito, muling binabasa ng screen na ito ang secure storage
  /// (`MpinLoginGate.resolve`) bago nito malaman kung MPIN o OTP form ang
  /// lalabas — at habang naghihintay, isang BUONG screen na kapareho ng splash
  /// ang ipinapakita. Kaya pagkatapos ng "Verify OTP" na loading ay may
  /// "splash" pa ulit bago ang MPIN screen. Sa handoff na ito, direkta na ang
  /// MPIN screen sa unang frame — walang paghihintay, walang splash.
  final MpinLoginChoice? handoff;

  @override
  ConsumerState<MobileLoginScreen> createState() => _MobileLoginScreenState();
}

class _MobileLoginScreenState extends ConsumerState<MobileLoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  // Lokal na 10-digit na numero (9XX XXX XXXX). Ang `+63` ay prefix na lang sa
  // field — hindi na kailangang i-type ng user ang `0` o ang `+63`.
  final _phoneMask = MaskTextInputFormatter(
    mask: '### ### ####',
    filter: {'#': RegExp(r'[0-9]')},
  );

  /// TEMP: hidden for now — flip back to `true` to restore the
  /// "or continue with" divider and the "Continue with Google" button.
  static const bool _showGoogleSignIn = false;

  bool _loading = false;
  bool _googleLoading = false;
  bool _googleFlowCancelled = false;
  Timer? _lockTimer;
  int _lockSecondsLeft = 0;

  // ── MPIN unlock (rider / lender) ─────────────────────────────────────────
  // Kapag naka-lock ang app (10-min idle) at may naka-set nang MPIN para sa
  // huling numerong ginamit, MPIN na lang ang hihingin — nasa itaas ang
  // numerong iyon, at ang digits ay ipinapasok sa 4 na tuldok + keypad.
  bool _mpinChecking = true;
  bool _showMpin = false;

  /// True kapag may naka-set nang MPIN para sa natandaang numero — kahit nasa
  /// "Mobile Number" form na (pagkatapos ng "Use another number"), hindi na
  /// dapat makalabas ang system back nang hindi dumadaan sa MPIN screen.
  bool _hasMpin = false;
  String? _mpinPhone;
  String? _mpinError;
  bool _mpinBusy = false;
  int _mpinLockSeconds = 0;
  Timer? _mpinLockTimer;

  /// Auto-hide ng validation message (hal. "Incorrect MPIN") — 3 segundo lang.
  Timer? _mpinErrorTimer;

  /// Tagal bago kusang mawala ang mensahe ng maling MPIN.
  static const _mpinErrorDuration = Duration(seconds: 3);
  final MpinPadController _padController = MpinPadController();
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
    // May handoff (galing OTP / MPIN setup) → hindi na kailangang mag-load:
    // ipakita agad ang MPIN screen na may numerong ginamit.
    final handoff = widget.handoff;
    if (handoff != null) {
      _mpinChecking = false;
      _showMpin = handoff.showMpin;
      _hasMpin = handoff.showMpin;
      _mpinPhone = handoff.phone;
    } else {
      _resolveMpinMode();
    }
    // May nakabinbing "Session Ended" na mensahe (hal. nag-expire ang session
    // habang nasa dashboard, kung kaya't hindi pa nasasalo ng `ref.listen` sa
    // ibaba) — ipakita ito sa unang frame. Ang OK nito ay maghahayag ng MPIN
    // screen na may numero sa likod.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(authStateProvider).securityMessage;
      if (pending == null || pending.trim().isEmpty) return;
      ref.read(authStateProvider.notifier).clearSecurityMessage();
      _showSecurityNotice(pending);
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _fadeController.dispose();
    _lockTimer?.cancel();
    _mpinLockTimer?.cancel();
    _mpinErrorTimer?.cancel();
    _padController.dispose();
    _lifecycleListener.dispose();
    super.dispose();
  }

  // ── MPIN unlock ──────────────────────────────────────────────────────────

  /// Tinitingnan kung dapat na MPIN ang hihingin sa page na ito: rider/lender
  /// ang huling naka-log in, may natandaang numero, at may naka-set nang MPIN
  /// sa device na ito.
  Future<void> _resolveMpinMode() async {
    // Lahat ng desisyon (natandaang numero + owner role + naka-set na MPIN) ay
    // nasa [MpinLoginGate] — hindi na nakakalat dito, at nasusubukan sa tests.
    final choice = await MpinLoginGate(
      mpin: ref.read(mpinServiceProvider),
    ).resolve();
    if (!mounted) return;
    setState(() {
      _mpinChecking = false;
      _mpinPhone = choice.phone;
      _hasMpin = choice.showMpin;
      _showMpin = choice.showMpin;
    });
  }

  /// Ang system back button: habang may naka-set na MPIN, hindi ito
  /// nagpapalabas sa login page — ibinabalik ito sa MPIN screen na may numero
  /// sa itaas.
  void _onLoginPageBack(bool didPop, Object? result) {
    if (didPop) return; // pinayagan na ng [PopScope.canPop] — huwag hadlangan
    if (!_hasMpin) return;
    if (_showMpin) return; // nasa MPIN screen na — manatili dito
    setState(() {
      _showMpin = true;
      _mpinError = null;
    });
  }

  /// Nagpapatakbo ng MPIN at ibinabalik ang session kapag tama.
  ///
  /// Ang MPIN ay lokal lang (hindi kailanman ipinapadala sa server), kaya ang
  /// pag-unlock ay: i-reset ang idle window (kagaya ng aktibidad) at muling
  /// buhayin ang session mula sa nakaimbak na refresh token. Kung expired na
  /// talaga ang token, saka lang babalik sa OTP login.
  Future<void> _submitMpin(String pin) async {
    if (_mpinBusy || _mpinLockSeconds > 0) return;
    _cancelMpinErrorTimer();
    setState(() {
      _mpinBusy = true;
      _mpinError = null;
    });
    // Naka-center na loading MODAL lang ang ipinapakita — hindi maliit na
    // spinner sa ilalim ng keypad, at hindi rin full-screen na loading ng buong
    // app. Nananatili ito hanggang matapos ang pag-restore ng session, kaya
    // isang tuloy-tuloy na loading lang ang nakikita: modal → dashboard.
    final hideLoading = showLoadingOverlay(context);
    late final MpinVerifyResult result;
    try {
      result = await ref.read(mpinServiceProvider).verify(pin);
    } catch (_) {
      hideLoading();
      if (!mounted) return;
      setState(() => _mpinBusy = false);
      _showMpinError('Something went wrong. Please try again.');
      _padController.clear();
      return;
    }
    // Mali ang MPIN (o naka-lock / wala nang MPIN) — isara agad ang modal para
    // makita ang error sa screen.
    if (result.status != MpinStatus.success) hideLoading();
    if (!mounted) return;

    switch (result.status) {
      case MpinStatus.success:
        await SecureStorage.saveLastActivity(DateTime.now().toUtc());
        if (kDebugMode) {
          final token = await SecureStorage.getAccessToken();
          final userId = await SecureStorage.getUserId();
          final role = await SecureStorage.getUserRole();
          final idle = await SecureStorage.getRemainingIdleTime();
          debugPrint('[MPIN] unlock: token=${token != null} userId=$userId '
              'role=$role idle=${idle?.inSeconds}s');
        }
        await ref
            .read(authStateProvider.notifier)
            .initialize(unlockedByMpin: true);
        // Isara ang modal bago lumipat — kung hindi, mananatili ito sa ibabaw
        // ng dashboard (walang sasara nito kapag na-dispose na ang screen).
        hideLoading();
        if (!mounted) return;
        // Kapag na-restore ang session, awtomatikong idadala na ng router sa
        // dashboard ang naka-authenticate na user.
        if (ref.read(authStateProvider).isAuthenticated) {
          if (kDebugMode) debugPrint('[MPIN] unlock → authenticated ✓');
          return;
        }
        // Hindi na ma-repair ang session (expired/invalid refresh token na ang
        // nakaimbak) — bumalik sa mobile number + OTP.
        if (kDebugMode) {
          debugPrint('[MPIN] unlock → BIGO: hindi na-restore ang session');
        }
        setState(() {
          _mpinBusy = false;
          _showMpin = false;
        });
        _padController.clear();
        _showError('Session expired. Please log in with your mobile number.');
        return;

      case MpinStatus.wrong:
        final left = result.attemptsLeft ?? 0;
        setState(() => _mpinBusy = false);
        _showMpinError(left > 0
            ? 'Incorrect MPIN. $left attempt${left == 1 ? '' : 's'} left.'
            : 'Incorrect MPIN.');
        _padController.clear();
        return;

      case MpinStatus.locked:
        // Ang lock countdown ay mananatili hangga't naka-lock (nila-clear ito
        // ng `_startMpinLock` kapag natapos na) — hindi ito awtomatikong
        // nawawala pagkatapos ng 3 segundo.
        _cancelMpinErrorTimer();
        setState(() {
          _mpinBusy = false;
          _mpinError = 'Too many attempts.';
        });
        _startMpinLock(result.lockRemaining ?? MpinService.lockoutDuration);
        _padController.clear();
        return;

      case MpinStatus.notSet:
        // Nabura na pala ang MPIN — bumalik sa OTP login (doon siya dadalhin
        // sa MPIN setup). Sabihan ito nang malinaw: kung hindi, parang
        // hindi gumagana ang MPIN screen (wala palang MPIN ang account).
        setState(() {
          _mpinBusy = false;
          _mpinError = null;
          _hasMpin = false;
          _showMpin = false;
        });
        _showError(
          'No MPIN is set for this account yet. Log in with your mobile '
          'number to create one.',
        );
        return;

      case MpinStatus.offline:
        // Server-side (account-level) na ang MPIN verification, kaya kailangan
        // ng internet para makapasok — hindi ito "maling MPIN".
        setState(() => _mpinBusy = false);
        _showMpinError(
            'Cannot verify your MPIN right now. Please check your internet '
            'connection and try again.');
        _padController.clear();
        return;
    }
  }

  /// Ipinapakita ang mensahe ng maling MPIN, tapos kusang tinatanggal ito
  /// pagkatapos ng [_mpinErrorDuration] (3 segundo) — para hindi ito manatiling
  /// nakabitin habang nagta-type muli ang user.
  void _showMpinError(String message) {
    _mpinErrorTimer?.cancel();
    setState(() => _mpinError = message);
    _mpinErrorTimer = Timer(_mpinErrorDuration, () {
      if (!mounted) return;
      setState(() => _mpinError = null);
    });
  }

  void _cancelMpinErrorTimer() {
    _mpinErrorTimer?.cancel();
    _mpinErrorTimer = null;
  }

  void _startMpinLock(Duration remaining) {
    _mpinLockTimer?.cancel();
    setState(() => _mpinLockSeconds = remaining.inSeconds.clamp(1, 600));
    _mpinLockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_mpinLockSeconds <= 1) {
        t.cancel();
        setState(() {
          _mpinLockSeconds = 0;
          _mpinError = null;
        });
      } else {
        setState(() => _mpinLockSeconds--);
      }
    });
  }

  String get _mpinLockLabel {
    final m = _mpinLockSeconds ~/ 60;
    final s = _mpinLockSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Lumabas sa MPIN view at bumalik sa "Mobile Number" form (hal. ibang
  /// account ang gustong gamitin).
  void _useAnotherNumber() {
    setState(() {
      _showMpin = false;
      _mpinError = null;
    });
    // Kalimutan ang naka-lock na numero (at ang owner nito) para sa susunod na
    // pagbukas ng app ay ang "Mobile Number" form na ang lumabas — hindi na ang
    // MPIN screen ng lumang numero. Mananatili pa rin ang MPIN ng account:
    // makikita ulit ito kapag nakapasok muli gamit ang OTP (ibinalik ng
    // `verifyOtp` ang parehong numero at owner).
    unawaited(SecureStorage.clearLoginPhone());
    unawaited(SecureStorage.clearLoginOwner());
  }

  /// Nagpapadala ng bagong OTP at dinadala ang user sa Verify OTP — doon lang
  /// siya muling makakapag-set ng bagong MPIN. (Walang Semaphore API pa sa
  /// ngayon, kaya `123456` ang tinatanggap na code ng backend.)
  ///
  /// Sadyang HINDI pa binubura dito ang lumang MPIN: kung mag-back ang user
  /// bago matapos (o hindi matuloy ang reset), mananatili ang dating MPIN at
  /// babalik siya sa MPIN screen na may numero — imbes na maiwang walang MPIN
  /// nang hindi sinasadya. Ang pagbura ay nangyayari pagkatapos ng matagumpay
  /// na OTP verification, bago ang bagong MPIN setup.
  Future<void> _resetMpin() async {
    final phone = _mpinPhone;
    if (_mpinBusy || phone == null || phone.isEmpty) return;
    setState(() {
      _mpinBusy = true;
      _mpinError = null;
    });
    // Naka-center na loading modal habang nagsasagawa ng bagong OTP.
    final hideLoading = showLoadingOverlay(context);
    // Bagong OTP bago ang muling pag-set — best effort lang; may "Resend code"
    // naman sa OTP screen kung hindi umabot ang SMS.
    try {
      await ref.read(authProvider.notifier).sendOtp(phone: phone);
    } catch (_) {}
    hideLoading();
    if (!mounted) return;
    setState(() => _mpinBusy = false);
    // `resetMpin: true` → ipapakita sa Verify OTP screen na pag-reset ng MPIN
    // ang ginagawa, hindi ordinaryong login.
    context.go(
      RouteConstants.otpVerify,
      extra: OtpFlowArgs(phone: phone, resetMpin: true),
    );
  }

  /// Ang lokal na 10-digit na naipasok (hal. `9123456789`).
  String get _rawPhone => _phoneMask.getUnmaskedText();

  /// Ang numerong ipinapadala sa API. Kailangang `09XXXXXXXXX` (11 digit) ang
  /// tinatanggap ng backend, kaya idinadagdag dito ang nangungunang `0` — sa UI
  /// lang naka-`+63` ang numero.
  String get _apiPhone => '0$_rawPhone';

  bool get _isPhoneValid =>
      _rawPhone.length == 10 && _rawPhone.startsWith('9');

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
    // No toast on mobile — the inline lock countdown in the form already
    // shows "Too many attempts / Try again in …".
  }

  Future<void> _sendOtp() async {
    if (!_isOnline || _lockSecondsLeft > 0) return;
    if (!_isPhoneValid) {
      _showError(
        'Enter a valid Philippine mobile number (+63 9XX XXX XXXX).',
      );
      return;
    }
    // Dismiss the keyboard right away so the loading state / next screen is
    // not covered by it.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _loading = true);
    final ok = await ref.read(authProvider.notifier).sendOtp(phone: _apiPhone);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      context.go(RouteConstants.otpVerify, extra: _apiPhone);
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
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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

  Widget _buildInfoMenuButton() {
    return PopupMenuButton<_InfoMenuAction>(
      tooltip: 'Menu',
      offset: const Offset(0, 48),
      color: Colors.white,
      elevation: 16,
      shadowColor: AppColors.deepNavy.withValues(alpha: 0.15),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: const Icon(Icons.more_horiz_rounded,
          color: AppColors.deepNavy, size: 24),
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

  /// Ang MPIN view: nasa itaas ang numerong ginamit sa login, ang 4 na tuldok,
  /// at ang numeric keypad na may nakabox na numero sa ibaba.
  Widget _buildMpinView() {
    final phone = _mpinPhone ?? '';
    final locked = _mpinLockSeconds > 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: SafeArea(
          child: Column(
            children: [
              // Top bar: menu right-aligned (kapareho ng login page)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildInfoMenuButton(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      // ── Brand ──
                      const Text(
                        'Jireta Loans',
                        style: TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepNavy,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '& CREDIT CORP 1966',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                          color: AppColors.gold,
                        ),
                      ),
                      // Ibaba ang "Enter MPIN" mula sa brand header.
                      const SizedBox(height: 112),

                      // ── Numero na ginamit sa login ──
                      // PINAKATAAS ito (inutos ng user): sa ilalim agad ng brand
                      // header, at nasa ITAAS ng "Enter MPIN" at ng 4 na tuldok.
                      // Ang "Use another number" ay nasa numerong ito:
                      // i-tap ito (ang switch icon) para bumalik sa
                      // "Mobile Number" form.
                      if (phone.isNotEmpty)
                        Center(
                          child: Tooltip(
                            message: 'Use another number',
                            child: Material(
                              color: const Color(0xFFF2F3F7),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: _mpinBusy ? null : _useAnotherNumber,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFE3E5EB)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Watawat ng Pilipinas — tugma sa `+63`
                                      // na prefix ng numero.
                                      const Text('🇵🇭',
                                          style: TextStyle(fontSize: 15)),
                                      const SizedBox(width: 8),
                                      Text(
                                        formatMpinPhone(phone),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4,
                                          color: AppColors.deepNavy,
                                          fontFeatures: [
                                            FontFeature.tabularFigures()
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Modern switch icon — i-tap para
                                      // lumipat sa ibang numero.
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: AppColors.deepNavy
                                              .withValues(alpha: 0.08),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.swap_horiz_rounded,
                                          size: 16,
                                          color: AppColors.deepNavy,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Bahagyang ibinaba mula sa numero (inutos ng user).
                      const SizedBox(height: 32),

                      // ── "Enter MPIN" — nasa ITAAS ng 4 na tuldok (inutos ng
                      // user). Nasa LABAS ito ng card; ang keypad lang ang nasa
                      // loob. ──
                      const Center(
                        child: Text(
                          'Enter MPIN',
                          style: TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepNavy,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── 4 na tuldok ──
                      Center(
                        child: MpinDots(
                          controller: _padController,
                          hasError: _mpinError != null && !locked,
                        ),
                      ),

                      // ── Mga mensahe: sa ILALIM ng 4 na tuldok ──
                      // Dalawa ang pwedeng lumabas dito:
                      //   • maling MPIN ("Incorrect MPIN. 2 attempts left.")
                      //     — kusang nawawala pagkatapos ng 3 segundo
                      //     (tingnan ang `_showMpinError`),
                      //   • lockout ("Too many attempts. Try again in …")
                      //     — nananatili hangga't naka-lock.
                      // Nakalaan ang espasyo (14 + 38) para hindi gumalaw ang
                      // keypad kapag lumabas ang mensahe. ──
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 38,
                        child: (locked || _mpinError != null)
                            ? Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      locked
                                          ? Icons.timer_rounded
                                          : Icons.error_outline_rounded,
                                      size: 15,
                                      color: AppColors.error,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        locked
                                            ? 'Too many attempts. Try again '
                                                'in $_mpinLockLabel.'
                                            : _mpinError!,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : null,
                      ),

                      // Nasa ibaba ang keypad — may pagitan sa mga tuldok.
                      const SizedBox(height: 126),

                      // ── Keypad (walang card) + Reset MPIN ──
                      Column(
                        children: [
                          MpinKeypadField(
                            controller: _padController,
                            enabled: !_mpinBusy && !locked,
                            hasError: _mpinError != null && !locked,
                            // Nasa itaas na (sa ilalim ng "Enter MPIN") ang
                            // 4 na tuldok.
                            showDots: false,
                            onCompleted: _submitMpin,
                          ),

                          // Ang "Too many attempts. Try again in …" ay nasa
                          // ITAAS na ngayon — sa ilalim ng 4 na tuldok, kasama
                          // ng mensahe ng maling MPIN.

                          // Nasa gitna ng screen na loading modal ang
                          // ipinapakita habang nag-ve-verify/nag-reset.
                          const SizedBox(height: 14),
                          Center(
                            child: TextButton(
                              onPressed: _mpinBusy ? null : _resetMpin,
                              child: const Text(
                                'Reset MPIN',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                  color: AppColors.deepNavy,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
    final authState = ref.watch(authStateProvider);
    // Habang nag-u-unlock gamit ang MPIN (naka-`_mpinBusy`) ang loading modal
    // sa gitna ang ipinapakita — hindi ang full-screen na loading ng buong app.
    //
    // Sa ibang pagkakataon (nagre-restore pa ang session pagka-open ng app, o
    // naka-authenticated na at papunta pa lang sa dashboard), ang BRANDED na
    // loading ang ipinapakita — logo + JIRETA + gold progress bar, kapareho ng
    // splash. Dati, hubad na spinper sa navy na screen ito, kaya parang
    // "loading screen" ang sumalubong sa user imbes na ang splash.
    if ((authState.isLoading || authState.isAuthenticated) && !_mpinBusy) {
      return const BrandedLoadingScreen();
    }

    // Habang tinitingnan kung MPIN na ang hihingin sa page na ito, huwag munang
    // ipakita ang phone form para hindi ito kumislap bago mag-switch.
    //
    // MAHALAGA: TAHIMIK na background lang ito — HINDI na branded loading.
    // Dating ang BrandedLoadingScreen (logo + JIRETA + gold progress bar) ang
    // ipinapakita dito, at dahil kapareho ito ng tunay na splash, ang dating
    // sa user ay "dalawang splash" pagka-open ng app. Ang landas na iyon ay
    // bihira na lang ding maabot: ang splash screen, OTP screen, at MPIN setup
    // ay nagpapasa na ng [MpinLoginChoice] (handoff), kaya alam na agad ng
    // screen na ito kung ano ang lalabas.
    if (_mpinChecking) {
      return const Scaffold(backgroundColor: Color(0xFFF7F8FA));
    }
    if (_showMpin) {
      // Nasa MPIN lock screen — hindi ito nilalabasan ng system back.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: _onLoginPageBack,
        child: _buildMpinView(),
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

    // Habang may naka-set na MPIN, ang system back ay hindi nagpapalabas ng
    // app: ibinabalik ito sa MPIN screen na may numero sa itaas.
    return PopScope(
      canPop: !_hasMpin,
      onPopInvokedWithResult: _onLoginPageBack,
      child: _buildLoginForm(canSendOtp, isOnline),
    );
  }

  Widget _buildLoginForm(bool canSendOtp, bool isOnline) {
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
        backgroundColor: const Color(0xFFF7F8FA),
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(
                children: [
                  // Top bar: menu right-aligned
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _buildInfoMenuButton(),
                    ),
                  ),
                  // Card: centered in the FULL remaining space — its position is
                  // locked and never moves, no matter where the brand text sits.
                  // The brand text floats at a fixed offset above the card.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Track the card's rise: the card is centered in the
                        // remaining space, so it moves up by half the keyboard
                        // height. The brand text moves up the same distance,
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
                                      // ── Card ──
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
                                                24, 24, 24, 24),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                // Handle
                                                const SizedBox(height: 4),
                                                const Text(
                                                  'Login',
                                                  style: TextStyle(
                                                    fontFamily:
                                                        'PlayfairDisplay',
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.deepNavy,
                                                    height: 1.1,
                                                  ),
                                                ),
                                                const SizedBox(height: 22),
                                                const Text(
                                                  'Mobile Number',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.deepNavy,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                // Premium input — simple (no extra smooth anim)
                                                TextFormField(
                                                  controller: _phoneCtrl,
                                                  keyboardType:
                                                      TextInputType.phone,
                                                  maxLength: 12,
                                                  inputFormatters: [_phoneMask],
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.deepNavy,
                                                    letterSpacing: 0.8,
                                                  ),
                                                  onChanged: (_) =>
                                                      setState(() {}),
                                                  decoration: InputDecoration(
                                                    hintText: '912 345 6789',
                                                    hintStyle: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: AppColors
                                                          .textTertiary
                                                          .withValues(
                                                              alpha: 0.7),
                                                      letterSpacing: 0.6,
                                                    ),
                                                    counterText: '',
                                                    filled: true,
                                                    fillColor:
                                                        const Color(0xFFF2F3F7),
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 14,
                                                            vertical: 16),
                                                    // +63 (Pilipinas) — lokal
                                                    // na 10-digit na numero
                                                    // (9XXX XXX XXX) ang type.
                                                    prefixIcon: const Padding(
                                                      padding:
                                                          EdgeInsets.only(
                                                              left: 14,
                                                              right: 6),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text('🇵🇭',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      16)),
                                                          SizedBox(width: 6),
                                                          Text(
                                                            '+63',
                                                            style: TextStyle(
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: AppColors
                                                                  .deepNavy,
                                                              letterSpacing:
                                                                  0.4,
                                                            ),
                                                          ),
                                                          SizedBox(width: 8),
                                                          // Manipis na
                                                          // divider sa
                                                          // pagitan ng
                                                          // prefix at
                                                          // numero.
                                                          SizedBox(
                                                            width: 1,
                                                            height: 20,
                                                            child: DecoratedBox(
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Color(
                                                                    0xFFD9DCE4),
                                                              ),
                                                            ),
                                                          ),
                                                          SizedBox(width: 6),
                                                        ],
                                                      ),
                                                    ),
                                                    prefixIconConstraints:
                                                        const BoxConstraints(
                                                      minWidth: 0,
                                                      minHeight: 0,
                                                    ),
                                                    suffixIcon: _phoneCtrl
                                                            .text.isNotEmpty
                                                        ? Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
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
                                                                          alpha:
                                                                              0.6),
                                                            ),
                                                          )
                                                        : null,
                                                    suffixIconConstraints:
                                                        const BoxConstraints(
                                                            minWidth: 0,
                                                            minHeight: 0),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: Color(
                                                                  0xFFE3E5EB)),
                                                    ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: AppColors
                                                                  .deepNavy,
                                                              width: 1.6),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),

                                                const SizedBox(height: 22),

                                                // ── Lock countdown inline ──
                                                if (_lockSecondsLeft > 0)
                                                  Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                            bottom: 14),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 14,
                                                        vertical: 12),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          AppColors.errorLight,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
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
                                                            color:
                                                                AppColors.error,
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                          child: const Icon(
                                                              Icons
                                                                  .timer_rounded,
                                                              size: 14,
                                                              color:
                                                                  Colors.white),
                                                        ),
                                                        const SizedBox(
                                                            width: 10),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              const Text(
                                                                'Too many attempts',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color:
                                                                      AppColors
                                                                          .error,
                                                                ),
                                                              ),
                                                              Text(
                                                                'Try again in $_lockLabel',
                                                                style:
                                                                    const TextStyle(
                                                                  fontSize: 11,
                                                                  color:
                                                                      AppColors
                                                                          .error,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Text(
                                                          _lockLabel,
                                                          style:
                                                              const TextStyle(
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
                                                                AppColors
                                                                    .deepNavy,
                                                                Color(
                                                                    0xFF1A3658),
                                                              ],
                                                              begin: Alignment
                                                                  .topLeft,
                                                              end: Alignment
                                                                  .bottomRight,
                                                            )
                                                          : null,
                                                      color: canSendOtp
                                                          ? null
                                                          : const Color(
                                                              0xFFE8E8EE),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                      boxShadow: canSendOtp
                                                          ? [
                                                              BoxShadow(
                                                                color: AppColors
                                                                    .deepNavy
                                                                    .withValues(
                                                                        alpha:
                                                                            0.35),
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
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(14),
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
                                                                strokeWidth:
                                                                    2.4,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            )
                                                          : Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Text(
                                                                  _lockSecondsLeft >
                                                                          0
                                                                      ? 'Locked · $_lockLabel'
                                                                      : 'Send OTP',
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        15.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    letterSpacing:
                                                                        0.3,
                                                                    color: canSendOtp
                                                                        ? Colors
                                                                            .white
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
                                                                              alpha: 0.22),
                                                                      shape: BoxShape
                                                                          .circle,
                                                                    ),
                                                                    child:
                                                                        const Icon(
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
                                                if (_showGoogleSignIn) ...[
                                                  const SizedBox(height: 18),

                                                  // Divider (short centered lines)
                                                  const Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      SizedBox(
                                                          width: 40,
                                                          child: Divider(
                                                              color: Color(
                                                                  0xFFE8E8EE),
                                                              thickness: 1)),
                                                      Padding(
                                                        padding: EdgeInsets
                                                            .symmetric(
                                                                horizontal: 12),
                                                        child: Text(
                                                          'or continue with',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: AppColors
                                                                .textTertiary,
                                                            letterSpacing: 0.3,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                          width: 40,
                                                          child: Divider(
                                                              color: Color(
                                                                  0xFFE8E8EE),
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
                                                      style: OutlinedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            Colors.white,
                                                        foregroundColor:
                                                            AppColors.deepNavy,
                                                        side: const BorderSide(
                                                            color: Color(
                                                                0xFFE8E8EE),
                                                            width: 1.2),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(14),
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
                                                                color: AppColors
                                                                    .deepNavy,
                                                              ),
                                                            )
                                                          : Image.asset(
                                                              'assets/images/continue_with_google.jpg',
                                                              width: 22,
                                                              height: 22,
                                                              fit: BoxFit
                                                                  .contain,
                                                              // Never render the raw "Unable to
                                                              // load asset" error box in the
                                                              // button if the asset is missing.
                                                              errorBuilder: (_,
                                                                      __,
                                                                      ___) =>
                                                                  const Icon(
                                                                Icons
                                                                    .g_mobiledata_rounded,
                                                                size: 22,
                                                                color: AppColors
                                                                    .deepNavy,
                                                              ),
                                                            ),
                                                      label: const Text(
                                                        'Continue with Google',
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: AppColors
                                                              .deepNavy,
                                                          letterSpacing: 0.1,
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
                                      const SizedBox(height: 8),

                                      // Offline banner
                                      if (!isOnline)
                                        const Padding(
                                          padding: EdgeInsets.fromLTRB(
                                              20, 0, 20, 12),
                                          child: OfflineToast(),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Brand text floating at a fixed offset — its height
                            // does not affect the card's centered position.
                            AnimatedPositioned(
                              // Pinned at the very top of the page (below the
                              // menu bar); rises out of the way when the
                              // keyboard opens (half its height, same as the
                              // card).
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              top: 32.0 - keyboardInset * 0.5,
                              left: 20,
                              right: 20,
                              child: const Column(
                                children: [
                                  Text(
                                    'Jireta Loans',
                                    style: TextStyle(
                                      fontFamily: 'PlayfairDisplay',
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.deepNavy,
                                      height: 1.15,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '& CREDIT CORP 1966',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2.6,
                                      color: AppColors.goldDark,
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

                  // Legal + version footer (hidden while the keyboard is open)
                  if (MediaQuery.of(context).viewInsets.bottom == 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Terms & Conditions · Privacy Policy (text links)
                          const LegalLinks(),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
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
                          SizedBox(
                            height: MediaQuery.of(context).padding.bottom + 4,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
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

/// "Successfully Logged Out" modal shown once right after a mobile logout.
/// The login page stays visible behind it (dim backdrop only) and the modal
/// auto-dismisses after 2 seconds, or immediately via the OK button.
class _LogoutSuccessModal extends StatefulWidget {
  const _LogoutSuccessModal();

  @override
  State<_LogoutSuccessModal> createState() => _LogoutSuccessModalState();
}

class _LogoutSuccessModalState extends State<_LogoutSuccessModal> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SuccessDialog(
        title: 'Successfully Logged Out',
        message: 'You have been logged out successfully.',
        buttonText: 'OK',
      ),
    );
  }
}

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
                borderRadius: BorderRadius.zero,
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: Color(0xFFE8E8EE)),
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
