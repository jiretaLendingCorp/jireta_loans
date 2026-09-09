// lib/presentation/features/auth/screens/terms_conditions_screen.dart
import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
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
import '../../../shared/providers/auth_state_provider.dart';
import '../providers/auth_provider.dart';

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

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  /// Per-account key suffix (same pattern as the per-account terms flag) so
  /// the name captured after acceptance lands on the right lender's upgrade
  /// form even on a shared device.
  String get _accountKeySuffix {
    final userId = ref.read(authStateProvider).user?.id ?? '';
    return userId.isEmpty ? '' : '_$userId';
  }

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

  Future<void> _saveNameAndGoHome() async {
    if (!_nameFormKey.currentState!.validate()) return;
    // Dismiss the keyboard right away so the loading state / next screen is
    // not covered by it.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _savingName = true);
    final prefs = await SharedPreferences.getInstance();
    final suffix = _accountKeySuffix;
    final userId = ref.read(authStateProvider).user?.id ?? '';
    final firstName = _firstNameCtrl.text.trim();
    final middleName = _middleNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final suffixName = _suffixCtrl.text.trim();
    final email = _emailCtrl.text.trim();
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
    // home screen. updateProfile also refetches the profile, so the dashboard
    // shows the new name immediately (no stale name).
    final platform = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android';
    await ref.read(lenderProfileProvider.notifier).updateProfile({
      'first_name': firstName,
      if (middleName.isNotEmpty) 'middle_name': middleName,
      'last_name': lastName,
      if (suffixName.isNotEmpty) 'suffix': suffixName,
      'email': email,
    });
    await ref.read(authProvider.notifier).acceptTerms(
          deviceId: 'default-device',
          platform: platform,
          appVersion: AppConstants.appVersion,
        );
    if (!mounted) return;
    // Diretso sa home ng lender pagkatapos ma-fill out ang name.
    context.go(RouteConstants.lenderDashboard);
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
                      margin: const EdgeInsets.symmetric(horizontal: 16),
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
                            _sectionTitle('1. Agreement to Terms'),
                            _body(
                              'By accessing and using the Jireta Loans & Credit Corp 1966 mobile application, you agree to be bound by these Terms and Conditions and our Privacy Policy.',
                            ),
                            _sectionTitle('2. Loan Services'),
                            _body(
                              'Jireta Loans & Credit Corp 1966 offers lending services ranging from ₱3,000 to ₱500,000 with an interest rate of 20% per loan term. Loan amounts and terms are subject to credit evaluation, account upgrade verification, and credit investigation.',
                            ),
                            _sectionTitle('3. Interest & Penalties'),
                            _body(
                              'All loans carry a 20% interest rate on the principal amount. A penalty of 20% on the total payable amount will be applied if payment is delayed by one (1) month or more.',
                            ),
                            _sectionTitle('4. Account Upgrade Requirements'),
                            _body(
                              'You are required to submit valid government-issued identification, proof of billing, selfie verification, and proof of income. All documents are subject to verification by authorized personnel.',
                            ),
                            _sectionTitle('5. Credit Investigation'),
                            _body(
                              'Loan applications are subject to a credit investigation conducted by authorized riders. You agree to cooperate with and receive visits from assigned investigators.',
                            ),
                            _sectionTitle('6. Payment Methods'),
                            _body(
                              'Payments may be made through GCash (via Xendit payment gateway), office cash payment, or rider cash collection. All transactions are recorded and receipts are issued.',
                            ),
                            _sectionTitle('7. Data Privacy'),
                            _body(
                              'We collect and process your personal information in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173) and our Privacy Policy. Your information is used solely for loan processing and account management.',
                            ),
                            _sectionTitle('8. Prohibited Acts'),
                            _body(
                              'You agree not to provide false information, commit fraud, or use the application for any unlawful purpose. Violations may result in account suspension, blacklisting, and legal action.',
                            ),
                            _sectionTitle('9. Governing Law'),
                            _body(
                              'These terms are governed by the laws of the Republic of the Philippines. Any disputes shall be resolved in the appropriate courts of the Philippines.',
                            ),
                            _sectionTitle('10. Contact'),
                            _body(
                              'For inquiries, please visit our office or contact our authorized personnel. Do not share your OTP or account credentials with anyone.',
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
          const Text(
            'Please provide your full legal name and email. These details\n'
            'will be auto-filled on your Account Upgrade.',
            style: TextStyle(
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
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _savingName ? null : _saveNameAndGoHome,
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
