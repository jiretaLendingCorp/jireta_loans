// lib/presentation/features/auth/screens/terms_conditions_screen.dart
import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter, SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../features/lender/profile/providers/lender_profile_provider.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../providers/auth_provider.dart';
import 'verify_email_screen.dart';

class TermsConditionsScreen extends ConsumerStatefulWidget {
  const TermsConditionsScreen({super.key});

  @override
  ConsumerState<TermsConditionsScreen> createState() =>
      _TermsConditionsScreenState();
}

class _TermsConditionsScreenState extends ConsumerState<TermsConditionsScreen> {
  bool _accepted = false;
  bool _privacyAccepted = false;
  bool _loading = false;
  final _scrollController = ScrollController();

  // After the one-time acceptance, the lender provides their full legal name
  // so the Account Upgrade "Personal Info" step can auto-fill it.
  bool _showNameForm = false;
  final _nameFormKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _savingName = false;

  /// Ang identifier na ginamit sa OTP login (numero O email). Kapag email ito,
  /// VERIFIED na ang address — hindi na ito muling hihingin sa "Fill In
  /// Information", at hindi na dadaan sa Verify Your Email.
  String? _loginIdentifier;

  bool get _emailVerifiedByLogin =>
      (_loginIdentifier ?? '').contains('@');

  @override
  void initState() {
    super.initState();
    unawaited(_loadLoginIdentifier());
  }

  Future<void> _loadLoginIdentifier() async {
    final identifier = await SecureStorage.getLoginIdentifier();
    if (!mounted) return;
    setState(() => _loginIdentifier = identifier);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // NOTE: ang per-account na suffix ay kinukuwenta na LANANG sa loob ng
  // `_saveNameAndGoHome` (may fallback sa `SecureStorage.getUserId()`), para
  // iisa lang ang pinagmulan nito dito at sa Verify Your Email screen.

  Future<void> _accept() async {
    if (!_accepted || !_privacyAccepted) return;
    setState(() => _loading = true);
    // NOTE: NOTHING is saved here (not even locally). The terms flag, the
    // personal info, and the database writes all happen ONLY after the
    // "Fill In Information" modal is filled out and validated (see
    // _saveNameAndGoHome). If the lender cancels the modal, no save occurs.
    if (!mounted) return;
    // Post-login one-time prompt: the lender is already authenticated.
    // Instead of leaving right away, collect the full legal name so the
    // Account Upgrade form can be auto-filled, then go straight home.
    if (ref.read(authStateProvider).isAuthenticated) {
      // Tiyakin munang alam kung email ang login identifier bago ipakita ang
      // modal — para hindi lumitaw ang Email Address field kahit isang frame.
      await _loadLoginIdentifier();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _showNameForm = true;
      });
      return;
    }
    if (kIsWeb) {
      context.go(RouteConstants.webLogin);
    } else {
      context.go(RouteConstants.mobileLogin);
    }
  }

  /// Isinasave ang "Fill In Information" (pangalan + email) at pagkatapos ay
  /// dinadala ang lender sa Verify Your Email screen — hindi deretso sa Home:
  /// kailangang kumpirmahin muna ang email sa link na ipinadala dito.
  Future<void> _saveNameAndVerifyEmail() async {
    if (!_nameFormKey.currentState!.validate()) return;
    // Dismiss the keyboard right away so the loading state / next screen is
    // not covered by it.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _savingName = true);
    final prefs = await SharedPreferences.getInstance();
    // Ang per-account na key ay dapat galing sa PAREHONG pinagmulan sa lahat ng
    // screen. Kapag walang `user` sa state (hal. na-restore lang na session na
    // may token at role), gamitin ang userId na naka-save sa SecureStorage —
    // kung hindi ay walang suffix na naisusulat dito, at HINDI ito mababasa ng
    // Verify Your Email screen (doon, "hindi nag-save" ang pakiramdam).
    var userId = ref.read(authStateProvider).user?.id ?? '';
    if (userId.isEmpty) {
      userId = await SecureStorage.getUserId() ?? '';
    }
    final suffix = userId.isEmpty ? '' : '_$userId';
    final firstName = _firstNameCtrl.text.trim();
    final middleName = _middleNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final suffixName = _suffixCtrl.text.trim();
    // Kapag email ang ginamit sa login (at sa paggawa ng account), verified na
    // ito sa OTP — iyon na ang email ng account, kaya hindi na hinihingi o
    // ipinapadala muli.
    final emailVerifiedByLogin = _emailVerifiedByLogin;
    final email = emailVerifiedByLogin
        ? (_loginIdentifier ?? '').trim()
        : _emailCtrl.text.trim();
    // Local acceptance flags — written here, ONLY after the modal info is
    // valid. Per-account key so the one-time prompt shows exactly once per
    // lender, even on a shared device.
    await prefs.setBool(AppConstants.termsAcceptedKey, true);
    if (userId.isNotEmpty) {
      await prefs.setBool(
          '${AppConstants.termsAcceptedKey}_$userId', true);
    }
    await prefs.setString(
        '${AppConstants.lenderFirstNameKey}$suffix', firstName);
    await prefs.setString(
        '${AppConstants.lenderMiddleNameKey}$suffix', middleName);
    await prefs.setString(
        '${AppConstants.lenderLastNameKey}$suffix', lastName);
    await prefs.setString(
        '${AppConstants.lenderSuffixKey}$suffix', suffixName);
    await prefs.setString(
        '${AppConstants.lenderEmailKey}$suffix', email);
    // DATABASE save happens ONLY here — after the modal info is filled out
    // and validated. Both the personal info (profile) and the one-time terms
    // acceptance are recorded server-side. These are AWAITED so the data is
    // guaranteed to be saved to the database BEFORE the lender lands on the
    // Verify Your Email screen. updateProfile also refetches the profile, so
    // the dashboard shows the new name immediately (no stale name).
    final platform = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android';
    // ── PANGALAN muna, tapos EMAIL sa HIWALAY na tawag ────────────────────
    // Ang email ay may uniqueness check sa server (409 DUPLICATE kapag may
    // ibang account nang gumagamit nito, 400 kapag hindi tanggap ang format).
    // Kapag isang tawag lang ang ginawa, ISASAMA ANG PANGALAN SA PAGTANGGI —
    // kaya kahit balido ang pangalan ay hindi ito nai-save ("hindi nag-save
    // ang Fill In Information").
    final nameOk =
        await ref.read(lenderProfileProvider.notifier).updateProfile({
      'first_name': firstName,
      if (middleName.isNotEmpty) 'middle_name': middleName,
      'last_name': lastName,
      if (suffixName.isNotEmpty) 'suffix': suffixName,
    });
    var emailOk = false;
    if (!emailVerifiedByLogin && email.isNotEmpty) {
      emailOk = await ref.read(lenderProfileProvider.notifier).updateProfile(
            {'email': email},
          );
    }
    if (kDebugMode) {
      debugPrint('[FILL-IN] save (Continue) name=$nameOk email=$emailOk '
          'error=${ref.read(lenderProfileProvider).error}');
    }
    await ref.read(authProvider.notifier).acceptTerms(
          deviceId: 'default-device',
          platform: platform,
          appVersion: AppConstants.appVersion,
        );
    if (!mounted) return;
    if (emailVerifiedByLogin) {
      // Email na ang ginamit sa login — verified na ito at nakasave na sa
      // account. Diretso na sa dashboard; wala nang Verify Your Email step.
      context.go(RouteConstants.lenderDashboard);
      return;
    }
    // ── Verification ng email: LINK ang ipinapadala (hindi OTP code) ────
    // Habang "Continuing..." pa ang button ay ipinapadala na ang mail, para
    // abot na ito pagdating sa Verify Your Email screen. Kapag nabigo, dinadala
    // pa rin ang mensahe ng server papunta sa screen (hindi ito tahimik na
    // nilalamon) — doon na lang ipapakita nang malinaw at mapipindot ang
    // "Resend Email".
    final sendError =
        await ref.read(authProvider.notifier).sendEmailVerification(
              email: email,
            );
    if (!mounted) return;
    // Hindi deretso sa home: kailangang kumpirmahin muna ang email sa
    // pamamagitan ng link na ipinadala doon.
    context.go(
      RouteConstants.verifyEmail,
      extra: VerifyEmailArgs(email: email, sendError: sendError),
    );
  }

  /// Backing out of the "Fill In Information" modal (system back or the close
  /// button) cancels the one-time acceptance and sends the lender to the Login
  /// page — NOT back to the dashboard. Nothing has been saved yet (all saves
  /// happen only on Continue), so the terms + info modal show again on the
  /// next login.
  ///
  /// A small centered loading dialog is shown while the logout runs so the
  /// X button never looks stuck.
  Future<void> _backToLogin() async {
    if (!mounted || !context.mounted) return;
    // Small centered loading dialog with a spinner while the logout runs.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      // Semi-transparent barrier — the "Fill In Information" modal stays
      // visible behind the loading box.
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            // Wide box, square corners (no border radius), with height.
            margin: const EdgeInsets.symmetric(horizontal: 24),
            width: double.infinity,
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Center the spinner + label inside the wide box.
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.deepNavy,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Loading...',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Hold the router redirect so it can't bounce back to the dashboard
    // while the session is being torn down.
    AppConstants.suppressLogoutRedirect = true;
    try {
      await ref.read(authStateProvider.notifier).logout();
    } catch (_) {}
    // Fire-and-forget: server-side session cleanup + re-enable router
    // redirects once it finishes.
    unawaited(_finishServerLogout());
    if (!mounted || !context.mounted) return;
    // Close the loading dialog, then land on the Login page.
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted || !context.mounted) return;
    if (kIsWeb) {
      context.go(RouteConstants.webLogin);
    } else {
      context.go(RouteConstants.mobileLogin);
    }
  }

  /// Server-side logout (best-effort, may hit the network) then re-enables
  /// the router redirects that were suppressed while leaving the terms page.
  Future<void> _finishServerLogout() async {
    try {
      await ref.read(authProvider.notifier).logout();
    } catch (_) {}
    AppConstants.suppressLogoutRedirect = false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // While the "Fill In Information" modal is open, the system back
      // button must NOT pop back to the dashboard — it logs out instead
      // and sends the lender to the Login page.
      canPop: !_showNameForm,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showNameForm) {
          _backToLogin();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              // Terms page — fully replaced by the modal after the lender
              // taps "Accept & Continue" (it disappears, the modal pops up).
              if (!_showNameForm)
                Column(
                children: [
                  // Header
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 32, 20, 16),
                    child: Column(
                      children: [
                        Text(
                          'Terms & Conditions',
                          style: TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepNavy,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  // Scrollable content box
                  Expanded(
                    child: Container(
                      // Desktop: hindi i-wide ang box — naka-cap sa 820px at
                      // naka-center; mobile: buong lapad (16px margins).
                      margin: EdgeInsets.symmetric(
                        horizontal: MediaQuery.of(context).size.width > 900
                            ? (MediaQuery.of(context).size.width - 820) / 2
                            : 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: AppColors.deepNavy.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.zero,
                        child: RawScrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          thickness: 5,
                          radius: const Radius.circular(8),
                          thumbColor: AppColors.border,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _body(
                              'By accessing and using the Jireta Loans & Credit Corp. Web and Mobile-Based Digitized Lending Management System, I acknowledge and agree to the following terms and conditions:',
                            ),
                            _sectionTitle('1. Account Security'),
                            _body(
                              'I agree to provide accurate information during registration and to keep my account credentials and verification codes confidential. I understand that I am responsible for activities performed through my account.',
                            ),
                            _sectionTitle('2. Personal Information'),
                            _body(
                              'I authorize the company to collect, store, and process my personal information as necessary for account management, loan processing, payment monitoring, and other legitimate lending-related purposes, subject to applicable data privacy laws and the company\'s Privacy Policy.',
                            ),
                            _sectionTitle('3. Accurate Information'),
                            _body(
                              'I confirm that the personal and other information I provide through the system is true, accurate, and complete to the best of my knowledge.',
                            ),
                            _sectionTitle('4. Proper Use of the System'),
                            _body(
                              'I agree to use the system only for its intended purposes, including viewing loan information, monitoring payment schedules, receiving notifications, and accessing authorized lending services.',
                            ),
                            _sectionTitle('5. Notifications and Updates'),
                            _body(
                              'I understand that the company may send relevant notifications regarding my account, loan application, payment schedule, payment status, and other important lending-related updates.',
                            ),
                            _sectionTitle('6. Acknowledgment of Terms'),
                            _body(
                              'I understand that accepting these Terms and Conditions allows me to proceed with system access. However, accepting these terms does not automatically constitute loan approval or a loan agreement.',
                            ),
                            _sectionTitle('7. Agreement and Acceptance'),
                            _body(
                              'By checking the acceptance box, I confirm that I have read, understood, and agreed to these Terms and Conditions.',
                            ),
                            const SizedBox(height: 12),
                            _body(
                              'Jireta Loans & Credit Corp.\nSta. Barbara, Pangasinan',
                            ),
                            const Divider(height: 32),
                            _sectionTitle('Privacy Policy Summary'),
                            _body(
                              'We collect your personal information including name, contact details, government IDs, financial information, and location data (for credit investigation and cash collection). This data is stored securely and used only for loan processing, identity verification, and regulatory compliance. You have the right to access, correct, and request deletion of your data.',
                            ),
                            const SizedBox(height: 20),
                            _checkbox(
                              value: _accepted,
                              onChanged: (v) =>
                                  setState(() => _accepted = v ?? false),
                              label:
                                  'I have read and agree to the Terms & Conditions',
                            ),
                            const SizedBox(height: 8),
                            _checkbox(
                              value: _privacyAccepted,
                              onChanged: (v) =>
                                  setState(() => _privacyAccepted = v ?? false),
                              label:
                                  'I agree to the Privacy Policy and data collection',
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed:
                                    (_accepted && _privacyAccepted && !_loading)
                                        ? _accept
                                        : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.gold,
                                  foregroundColor: AppColors.deepNavy,
                                  disabledBackgroundColor:
                                      AppColors.gold.withValues(alpha: 0.3),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.deepNavy,
                                        ),
                                      )
                                    : const Text(
                                        'Accept & Continue',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
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
                ],
              ),
              // "Fill In Information" modal — takes over the whole screen:
              // dark backdrop + centered card that pops in, like a dialog.
              if (_showNameForm)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.7, end: 1),
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          elevation: 8,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: _buildNameForm(),
                          ),
                        ),
                      ),
                    ),
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

  Widget _buildNameForm() {
    return Form(
      key: _nameFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded,
                  size: 24, color: AppColors.deepNavy),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Fill In Information',
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy,
                  ),
                ),
              ),
              // Close — same as the system back: logs out → Login page.
              IconButton(
                onPressed: _savingName ? null : _backToLogin,
                icon: const Icon(Icons.close_rounded,
                    size: 22, color: AppColors.textSecondary),
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _emailVerifiedByLogin
                ? 'Please provide your full legal name. These details\n'
                    'will be auto-filled on your Account Upgrade.'
                : 'Please provide your full legal name and email. These details\n'
                    'will be auto-filled on your Account Upgrade.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _firstNameCtrl,
            maxLength: 100,
            decoration: _fieldDecoration('First Name *'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'First name is required'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _middleNameCtrl,
            maxLength: 2,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z.]')),
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: _fieldDecoration('Middle Name (Optional)'),
            validator: (v) {
              if (v == null || v.isEmpty) return null;
              if (!RegExp(r'^[a-zA-Z.]{1,2}$').hasMatch(v)) {
                return 'Max 2 letters or "." only';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _lastNameCtrl,
            maxLength: 100,
            decoration: _fieldDecoration('Last Name *'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Last name is required'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _suffixCtrl,
            maxLength: 20,
            decoration: _fieldDecoration('Suffix (Optional)',
                hint: 'e.g. Jr., Sr., III'),
          ),
          if (!_emailVerifiedByLogin) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              maxLength: 255,
              keyboardType: TextInputType.emailAddress,
              decoration: _fieldDecoration('Email Address *'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Email address is required';
                }
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                    .hasMatch(v.trim())) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _savingName ? null : _saveNameAndVerifyEmail,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.deepNavy,
                disabledBackgroundColor:
                    AppColors.gold.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _savingName
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.deepNavy,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Continuing...',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'Continue',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      counterText: '',
      labelStyle: const TextStyle(
        fontSize: 13,
        color: AppColors.textSecondary,
      ),
      hintStyle: const TextStyle(
        fontSize: 13,
        color: AppColors.textTertiary,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.deepNavy, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.deepNavy,
          ),
        ),
      );

  Widget _body(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      );

  Widget _checkbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String label,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.deepNavy,
          checkColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}
