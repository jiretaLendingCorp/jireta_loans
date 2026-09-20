// lib/presentation/features/auth/screens/mpin_setup_screen.dart
//
// Unang hakbang pagkatapos ma-verify ang OTP ng rider / lender: mag-set ng
// 4-digit MPIN. Ito na ang gagamitin sa SUSUNOD na login kaya hindi ito
// matatapos hangga't walang naka-save na MPIN.
//
// Ipinapakita sa itaas ang numerong ginamit sa login, at ang MPIN ay ipinapasok
// sa 4 na tuldok + numeric keypad (walang system keyboard).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_constants.dart';
import '../../../../core/security/mpin_login_gate.dart';
import '../../../../core/security/mpin_service.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../../../shared/widgets/dialogs/loading_dialog.dart';
import '../../../shared/widgets/security/mpin_keypad.dart';

/// Hakbang ng setup: gumawa ng bagong MPIN, tapos kumpirmahin.
enum _SetupStep { create, confirm }

class MpinSetupScreen extends ConsumerStatefulWidget {
  const MpinSetupScreen({super.key});

  @override
  ConsumerState<MpinSetupScreen> createState() => _MpinSetupScreenState();
}

class _MpinSetupScreenState extends ConsumerState<MpinSetupScreen> {
  final _padController = MpinPadController();

  _SetupStep _step = _SetupStep.create;
  String _firstEntry = '';
  String? _error;
  bool _busy = false;
  String? _phone;

  /// Auto-hide ng mga pansamantalang mensahe (hal. "MPIN did not match.") —
  /// 3 segundo lang, para hindi ito manatiling nakabitin habang nagta-type
  /// muli ang user.
  Timer? _errorTimer;

  /// Tagal bago kusang mawala ang mensaheng tulad ng hindi pagtutugma ng MPIN.
  static const _errorVisibleDuration = Duration(seconds: 3);

  /// Ang nakalaang taas ng slot ng mensahe sa ilalim ng 4 na tuldok. Nakalaan
  /// ito kahit walang mensahe para hindi gumalaw ang keypad.
  static const _errorSlotMinHeight = 38.0;

  /// Pagitan ng 4 na tuldok at ng keypad. Ang dating 196 ay binawasan ng
  /// `_errorSlotMinHeight + 14` (ang slot ng mensahe), kaya kapareho pa rin ng
  /// dating posisyon ang keypad.
  static const _dotsToKeypadGap = 144.0;

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _padController.dispose();
    super.dispose();
  }

  /// Ipinapakita ang mensahe sa ilalim ng 4 na tuldok, tapos kusang tinatanggal
  /// pagkatapos ng [_errorVisibleDuration] (3 segundo).
  void _showError(String message) {
    _errorTimer?.cancel();
    setState(() => _error = message);
    _errorTimer = Timer(_errorVisibleDuration, () {
      if (!mounted) return;
      setState(() => _error = null);
    });
  }

  Future<void> _loadPhone() async {
    final phone = await SecureStorage.getLoginPhone();
    if (!mounted) return;
    setState(() => _phone = phone);
  }

  /// Kapag puno na ang 4 na digit — depende sa hakbang kung i-save o
  /// ikumpara muna sa unang naipasok.
  Future<void> _onCompleted(String pin) async {
    if (_busy) return;

    if (_step == _SetupStep.create) {
      setState(() {
        _firstEntry = pin;
        _step = _SetupStep.confirm;
        _error = null;
      });
      _padController.clear();
      return;
    }

    if (pin != _firstEntry) {
      setState(() {
        _firstEntry = '';
        _step = _SetupStep.create;
      });
      _showError('MPIN did not match. Please enter it again.');
      _padController.clear();
      return;
    }

    setState(() => _busy = true);
    // Naka-center na loading modal (puting box + spinner + "Loading…") imbes na
    // maliit na spinner sa ilalim ng keypad — kapareho ng loading modal ng
    // "Fill In Information" dialog sa app.
    final hideLoading = showLoadingOverlay(context);

    try {
      await ref.read(mpinServiceProvider).setMpin(pin);
      // Bahagyang paghinto para kitang-kita ang loading bago lumipat.
      await Future.delayed(const Duration(milliseconds: 900));
      hideLoading();
      if (!mounted) return;
      // Naka-save na ang MPIN. Hindi deretso sa dashboard: inilalagay muna ang
      // app sa locked state at bumabalik sa login page, kung saan ipapakita ang
      // numerong ginamit at hihingin ang bagong MPIN — para makita mismo ng
      // user na ito na ang gagamitin sa susunod na login.
      await _goToLoginWithMpin();
    } on MpinChangeLimitException catch (e) {
      hideLoading();
      if (!mounted) return;
      // Nananatili ang mensaheng ito (hindi ito kusang nawawala) — kaya dapat
      // kanselahin ang anumang naka-pending na auto-hide timer.
      _errorTimer?.cancel();
      setState(() {
        _busy = false;
        _error = 'Limit reached: you can only change your MPIN '
            '${MpinService.maxChangesPerWindow} times within 15 days. '
            'You can change it again in ${_formatRetry(e.retryAfter)}.';
        _firstEntry = '';
        _step = _SetupStep.create;
      });
      _padController.clear();
    } catch (_) {
      hideLoading();
      if (!mounted) return;
      _errorTimer?.cancel();
      setState(() {
        _busy = false;
        _error = 'Could not save your MPIN. Please try again.';
        _firstEntry = '';
        _step = _SetupStep.create;
      });
      _padController.clear();
    }
  }

  Future<void> _goToLoginWithMpin() async {
    await ref.read(authStateProvider.notifier).lockForMpinUnlock();
    if (!mounted) return;
    // Handoff: alam na ng login page ang numero at ang bagong naka-set na MPIN,
    // kaya deretso agad ito sa MPIN screen — walang splash-look na loading sa
    // gitna ng MPIN setup at ng login page.
    context.go(
      RouteConstants.mobileLogin,
      extra: MpinLoginChoice(showMpin: true, phone: _phone),
    );
  }

  /// "3 days and 4 hours" / "5 hours" / "12 minutes".
  String _formatRetry(Duration d) {
    if (d.inDays >= 1) {
      final days = d.inDays;
      final hours = d.inHours % 24;
      final dayLabel = '$days day${days == 1 ? '' : 's'}';
      return hours > 0
          ? '$dayLabel and $hours hour${hours == 1 ? '' : 's'}'
          : dayLabel;
    }
    if (d.inHours >= 1) {
      return '${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
    }
    final mins = d.inMinutes < 1 ? 1 : d.inMinutes;
    return '$mins minute${mins == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final isConfirm = _step == _SetupStep.confirm;
    final title = isConfirm ? 'Confirm MPIN' : 'Create Your MPIN';
    final subtitle = isConfirm
        ? 'Re-enter your 4-digit MPIN to confirm.'
        : 'This 4-digit MPIN is what you will use to log in next time.';
    final phone = _phone;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      // Kailangang ma-set ang MPIN bago makalabas — walang back button at
      // walang swipe-back.
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFFF7F8FA),
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        // Walang icon sa itaas. Pagkakasunod-sunod:
                        // pamagat → subtitle → numero → "Enter MPIN" → 4 na
                        // tuldok → keypad (walang card sa likod nito).
                        const SizedBox(height: 76),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepNavy,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 22),

                        // ── Number, "Enter MPIN", at ang 4 na tuldok: nasa
                        // LABAS ng card (ang keypad lang ang nasa loob nito).
                        // Nasa itaas ang numero ng account, sa ibaba nito ang
                        // "Enter MPIN", at sa ibaba ng MPIN ang 4 na tuldok. ──
                        if (phone != null)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F3F7),
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
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 40),

                        const Center(
                          child: Text(
                            'Enter MPIN',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'PlayfairDisplay',
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.deepNavy,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Center(
                          child: MpinDots(
                            controller: _padController,
                            hasError: _error != null,
                          ),
                        ),
                        // ── Validation message: nasa ILALIM ng 4 na tuldok ──
                        // (dati ay nasa ibaba pa ng keypad). Nakalaan ang
                        // taas kahit walang mensahe, kaya hindi gumagalaw ang
                        // keypad kapag lumabas o nawala ito.
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                              minHeight: _errorSlotMinHeight),
                          child: _error == null
                              ? const SizedBox.shrink()
                              : Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.error_outline_rounded,
                                          size: 16, color: AppColors.error),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          _error!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            height: 1.35,
                                            color: AppColors.error,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),

                        // Nasa ibaba ang keypad — may pagitan sa mga tuldok.
                        const SizedBox(height: _dotsToKeypadGap),

                        // ── Keypad (walang card sa likod nito) ──
                        Center(
                          child: MpinKeypadField(
                            controller: _padController,
                            enabled: !_busy,
                            hasError: _error != null,
                            // Nasa itaas na (sa ibaba ng "Enter MPIN") ang
                            // tuldok.
                            showDots: false,
                            onCompleted: _onCompleted,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


