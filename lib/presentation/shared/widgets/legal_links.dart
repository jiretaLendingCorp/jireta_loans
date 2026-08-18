// lib/presentation/shared/widgets/legal_links.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../features/lender/profile/screens/widgets/legal_info_sheet.dart';

/// A row of tappable "Terms & Conditions" and "Privacy Policy" links used on
/// light-background screens. Tapping either link opens a bottom sheet with the
/// full legal content.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, this.textColor = AppColors.textSecondary});

  final Color textColor;

  void _showTerms(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LegalInfoSheet(
        title: 'Terms & Conditions',
        sections: [
          LegalSection(
            title: '1. Agreement to Terms',
            body:
                'By accessing and using the Jireta Loans & Credit Corp 1966 mobile application, you agree to be bound by these Terms and Conditions and our Privacy Policy.',
          ),
          LegalSection(
            title: '2. Loan Services',
            body:
                'Jireta Loans & Credit Corp 1966 offers lending services ranging from \u20B13,000 to \u20B1500,000 with an interest rate of 20% per loan term. Loan amounts and terms are subject to credit evaluation, account upgrade verification, and credit investigation.',
          ),
          LegalSection(
            title: '3. Interest & Penalties',
            body:
                'All loans carry a 20% interest rate on the principal amount. A penalty of 20% on the total payable amount will be applied if payment is delayed by one (1) month or more.',
          ),
          LegalSection(
            title: '4. Account Upgrade Requirements',
            body:
                'You are required to submit valid government-issued identification, proof of billing, selfie verification, and proof of income. All documents are subject to verification by authorized personnel.',
          ),
          LegalSection(
            title: '5. Credit Investigation',
            body:
                'Loan applications are subject to a credit investigation conducted by authorized riders. You agree to cooperate with and receive visits from assigned investigators.',
          ),
          LegalSection(
            title: '6. Payment Methods',
            body:
                'Payments may be made through GCash (via Xendit payment gateway), office cash payment, or rider cash collection. All transactions are recorded and receipts are issued.',
          ),
          LegalSection(
            title: '7. Data Privacy',
            body:
                'We collect and process your personal information in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173) and our Privacy Policy. Your information is used solely for loan processing and account management.',
          ),
          LegalSection(
            title: '8. Prohibited Acts',
            body:
                'You agree not to provide false information, commit fraud, or use the application for any unlawful purpose. Violations may result in account suspension, blacklisting, and legal action.',
          ),
          LegalSection(
            title: '9. Governing Law',
            body:
                'These terms are governed by the laws of the Republic of the Philippines. Any disputes shall be resolved in the appropriate courts of the Philippines.',
          ),
          LegalSection(
            title: '10. Contact',
            body:
                'For inquiries, please visit our office or contact our authorized personnel. Do not share your OTP or account credentials with anyone.',
          ),
        ],
      ),
    );
  }

  void _showPrivacy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LegalInfoSheet(
        title: 'Privacy Policy',
        sections: [
          LegalSection(
            title: 'Data We Collect',
            body:
                'We collect your personal information including name, contact details, government IDs, financial information, and location data (for credit investigation and cash collection).',
          ),
          LegalSection(
            title: 'How We Use Your Data',
            body:
                'Your data is stored securely and used only for loan processing, identity verification, and regulatory compliance.',
          ),
          LegalSection(
            title: 'Your Rights',
            body:
                'You have the right to access, correct, and request deletion of your data in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173).',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget link(String label, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        link('Terms & Conditions', () => _showTerms(context)),
        Text(
          '·',
          style: TextStyle(fontSize: 12, color: textColor),
        ),
        link('Privacy Policy', () => _showPrivacy(context)),
      ],
    );
  }
}
