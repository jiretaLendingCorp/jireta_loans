// lib/presentation/features/auth/screens/terms_conditions_screen.dart
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
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

  Future<void> _accept() async {
    if (!_accepted || !_privacyAccepted) return;
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.termsAcceptedKey, true);
    // FIX: Record the acceptance server-side too (users.terms_accepted_at +
    // terms_consent_logs). The local flag is the first-run gate; the server
    // record makes it durable per account so it never re-prompts after sign-out.
    final platform = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android';
    await ref.read(authProvider.notifier).acceptTerms(
          deviceId: 'default-device',
          platform: platform,
          appVersion: AppConstants.appVersion,
        );
    if (!mounted) return;
    // Web browser (Head Manager / Employee) → email+password login
    // Mobile app (Rider / Lender) → phone OTP login
    if (kIsWeb) {
      context.go(RouteConstants.webLogin);
    } else {
      context.go(RouteConstants.mobileLogin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.navyOverlay,
      child: Scaffold(
        backgroundColor: AppColors.deepNavy,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.gold),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(AssetConstants.logoJpg,
                            fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Jireta Loans & Credit Corp',
                      style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Terms & Conditions',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        letterSpacing: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
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
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                color: AppColors.deepNavy,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  children: [
                    _checkbox(
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v ?? false),
                      label: 'I have read and agree to the Terms & Conditions',
                    ),
                    const SizedBox(height: 8),
                    _checkbox(
                      value: _privacyAccepted,
                      onChanged: (v) =>
                          setState(() => _privacyAccepted = v ?? false),
                      label:
                          'I agree to the Privacy Policy and data collection',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_accepted && _privacyAccepted && !_loading)
                            ? _accept
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.deepNavy,
                          disabledBackgroundColor: AppColors.gold.withValues(
                            alpha: 0.3,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
            ],
          ),
        ),
      ),
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
          activeColor: AppColors.gold,
          checkColor: AppColors.deepNavy,
          side: const BorderSide(color: Colors.white54),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ),
      ],
    );
  }
}
