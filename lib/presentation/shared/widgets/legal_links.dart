// lib/presentation/shared/widgets/legal_links.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../features/lender/profile/screens/widgets/legal_info_sheet.dart';

/// Buong nilalaman ng Terms & Conditions — ISANG pinagmumulan lang ito para sa
/// [LegalLinks] ng profile at sa "I have read and agree…" na text sa ibang
/// screens (hal. loan-apply wizard).
const List<LegalSection> kTermsAndConditionsSections = [
  LegalSection(
    title: 'Introduction',
    body:
        'By accessing and using the Jireta Loans & Credit Corp. Web and Mobile-Based Digitized Lending Management System, I acknowledge and agree to the following terms and conditions:',
  ),
  LegalSection(
    title: '1. Account Security',
    body:
        'I agree to provide accurate information during registration and to keep my account credentials and verification codes confidential. I understand that I am responsible for activities performed through my account.',
  ),
  LegalSection(
    title: '2. Personal Information',
    body:
        'I authorize the company to collect, store, and process my personal information as necessary for account management, loan processing, payment monitoring, and other legitimate lending-related purposes, subject to applicable data privacy laws and the company\'s Privacy Policy.',
  ),
  LegalSection(
    title: '3. Accurate Information',
    body:
        'I confirm that the personal and other information I provide through the system is true, accurate, and complete to the best of my knowledge.',
  ),
  LegalSection(
    title: '4. Proper Use of the System',
    body:
        'I agree to use the system only for its intended purposes, including viewing loan information, monitoring payment schedules, receiving notifications, and accessing authorized lending services.',
  ),
  LegalSection(
    title: '5. Notifications and Updates',
    body:
        'I understand that the company may send relevant notifications regarding my account, loan application, payment schedule, payment status, and other important lending-related updates.',
  ),
  LegalSection(
    title: '6. Acknowledgment of Terms',
    body:
        'I understand that accepting these Terms and Conditions allows me to proceed with system access. However, accepting these terms does not automatically constitute loan approval or a loan agreement.',
  ),
  LegalSection(
    title: '7. Agreement and Acceptance',
    body:
        'By checking the acceptance box, I confirm that I have read, understood, and agreed to these Terms and Conditions.',
  ),
  LegalSection(
    title: 'Jireta Loans & Credit Corp.',
    body: 'Sta. Barbara, Pangasinan',
  ),
];

/// Buong nilalaman ng **loan-confirmation** Terms and Conditions — ito ang
/// binubuksan ng "Terms and Conditions" link sa loan application, bago ang
/// "Submit Application".
///
/// HIWALAY ito sa [kTermsAndConditionsSections] (account terms ng profile at ng
/// web footer): loan-specific ang mga pangako dito (amount, interest, schedule,
/// release, late payments, electronic confirmation), kaya hindi ito dapat
/// palitan ng pangkalahatang account terms sa gitna ng loan application.
const List<LegalSection> kLoanConfirmationTermsSections = [
  // Pareho ito ng unang loan application (Required Documents step): may
  // pamagat na linya bago ang numbered na sections.
  LegalSection(
    title: 'JIRETA LOANS & CREDIT CORP.',
    body: 'Loan Amount, Payment, and Process Confirmation',
  ),
  LegalSection(
    title: '1. Loan Amount',
    body:
        'I confirm that I have reviewed the requested loan amount and understand that the final approved loan amount will be determined by Jireta Loans & Credit Corp. The amount approved by the company may differ from the amount originally requested.',
  ),
  LegalSection(
    title: '2. Interest and Total Repayment',
    body:
        'I understand that the applicable interest rate, interest computation, total amount payable, and any applicable fees or deductions must be clearly disclosed to me before I accept the final loan agreement.',
  ),
  LegalSection(
    title: '3. Payment Schedule',
    body:
        'I acknowledge that I must review my payment schedule, including the amount due per installment, payment frequency, due dates, and final payment deadline. I agree to make payments according to the schedule stated in my accepted loan agreement.',
  ),
  LegalSection(
    title: '4. Payment Methods',
    body:
        'I understand that payments may be made through the company\'s authorized payment methods, such as:\n'
        '\u2022 Payment collected by an authorized company rider.\n'
        '\u2022 Payment made directly at the company office.\n'
        '\u2022 Online payment through an authorized payment provider, when available.\n'
        'I understand that I should keep the receipt or electronic confirmation as proof of payment.',
  ),
  LegalSection(
    title: '5. Loan Release Process',
    body:
        'I understand that the release of the approved loan amount is subject to the company\'s verification, approval, and release procedures. The loan may be delivered through an authorized company representative or released at the company office, as applicable.',
  ),
  LegalSection(
    title: '6. Payment Recording and Monitoring',
    body:
        'I understand that my payment records and outstanding balance will be monitored through the company\'s lending management system. I may review my available loan information and payment status through the authorized interface.',
  ),
  LegalSection(
    title: '7. Late or Missed Payments',
    body:
        'I understand that missed or late payments must be handled according to the terms disclosed in my loan agreement and applicable laws. Any penalties, additional charges, or other consequences must be clearly disclosed before I agree to them.',
  ),
  LegalSection(
    title: '8. Confirmation of Loan Details',
    body:
        'Before confirming the loan, I will verify the following:\n'
        '\u2022 Approved loan amount.\n'
        '\u2022 Interest rate and interest computation.\n'
        '\u2022 Total repayment amount.\n'
        '\u2022 Installment amount and payment frequency.\n'
        '\u2022 Payment due dates and final deadline.\n'
        '\u2022 Applicable fees, deductions, and other disclosed charges.\n'
        '\u2022 Loan release method and repayment procedures.',
  ),
  LegalSection(
    title: '9. Accuracy and Disputes',
    body:
        'I agree to notify the company promptly if I discover an error in my loan details or payment records. I understand that I may request clarification or correction through the company\'s authorized personnel.',
  ),
  LegalSection(
    title: '10. Voluntary Acceptance',
    body:
        'I confirm that I have had the opportunity to review the loan details and ask questions before accepting the agreement. I understand that I should not confirm the loan if any amount, charge, or payment condition is unclear.',
  ),
  LegalSection(
    title: '11. Electronic Confirmation',
    body:
        'By checking the confirmation box and selecting the confirmation button, I acknowledge that I have reviewed the displayed loan details and agree to proceed under the final loan agreement presented to me. The system should record the confirmation date, time, and applicable loan details.',
  ),
  LegalSection(
    title: 'Jireta Loans & Credit Corp.',
    body: 'Sta. Barbara, Pangasinan',
  ),
];

/// Buong nilalaman ng Privacy Policy — ISANG pinagmumulan lang ito para sa
/// profile, sa footer ng web login, at sa mga link sa ibang screens.
const List<LegalSection> kPrivacyPolicySections = [
  LegalSection(
    title: '1. Introduction',
    body:
        'Jireta Loans & Credit Corp. respects the privacy of its lenders, employees, riders, and other authorized users. This Privacy Policy explains how the company collects, uses, stores, protects, and manages personal information through its Web and Mobile-Based Digitized Lending Management System.\n\n'
        'The company aims to handle personal information responsibly and in accordance with the Philippine Data Privacy Act of 2012 (Republic Act No. 10173) and other applicable laws and regulations.',
  ),
  LegalSection(
    title: '2. Information We Collect',
    body:
        'Depending on the user\'s role and activities in the system, the company may collect the following information:\n\n'
        '• Personal Information: Full name, address, birthday, contact number, and other necessary identification details.\n'
        '• Account Information: Username for authorized staff accounts, registered mobile number, and OTP verification records.\n'
        '• Loan Information: Requested and approved loan amounts, interest rates, outstanding balances, payment schedules, due dates, and loan status.\n'
        '• Payment Information: Payment amounts, payment dates, collection status, receipts or transaction references, and other necessary payment records.\n'
        '• Business Information: Relevant business name, business address, and other information required for loan assessment.\n'
        '• Related-Person Information: Necessary details about relatives or connections when legitimately required for loan processing, subject to applicable privacy requirements.\n'
        '• System Records: Relevant login activity, account actions, and security logs used to protect the system and maintain accurate records.\n\n'
        'The company will collect only information that is necessary and proportionate to its legitimate purposes.',
  ),
  LegalSection(
    title: '3. Purpose of Collecting Information',
    body:
        'Personal information may be processed for the following purposes:\n\n'
        '1. To register and manage authorized user accounts.\n'
        '2. To verify user identity through the applicable authentication process, including mobile OTP verification.\n'
        '3. To receive, review, approve, or reject loan applications.\n'
        '4. To maintain accurate lender profiles and loan records.\n'
        '5. To calculate and monitor outstanding balances and repayment schedules.\n'
        '6. To record payments and update payment status.\n'
        '7. To coordinate authorized loan releases and payment collections.\n'
        '8. To send relevant account, loan, payment, and security notifications.\n'
        '9. To generate operational reports for authorized company personnel.\n'
        '10. To prevent unauthorized access, investigate discrepancies, and comply with applicable legal obligations.',
  ),
  LegalSection(
    title: '4. How We Use and Share Information',
    body:
        'Access to personal information will be limited to authorized personnel according to their assigned roles and responsibilities.\n\n'
        'Information may be shared with authorized employees, riders, payment service providers, technology providers, or competent authorities when necessary for a disclosed and lawful purpose.\n\n'
        'The company will not treat access to a user\'s records as permission to disclose those records for unrelated purposes. Any sharing of personal information will be subject to applicable legal requirements and appropriate safeguards.',
  ),
  LegalSection(
    title: '5. Data Storage and Retention',
    body:
        'Personal information may be stored in the company\'s authorized databases and systems to support account management, loan processing, payment monitoring, recordkeeping, and compliance.\n\n'
        'Information will be retained only for as long as necessary for the declared purposes, applicable legal requirements, legitimate business needs, or the establishment and defense of legal claims.\n\n'
        'When information is no longer necessary and no legal retention requirement applies, it will be securely deleted, destroyed, or anonymized as appropriate.',
  ),
  LegalSection(
    title: '6. Data Security',
    body:
        'The company will implement reasonable and appropriate organizational, physical, and technical safeguards to protect personal information against unauthorized access, disclosure, alteration, loss, and destruction.\n\n'
        'Depending on the system\'s implemented capabilities, these safeguards may include role-based access restrictions, account authentication, secure database access, access monitoring, and appropriate backup procedures.\n\n'
        'Authorized users must protect their login credentials and OTP codes and must immediately report suspected account compromise or unauthorized access.',
  ),
  LegalSection(
    title: '7. User Privacy Rights',
    body:
        'Subject to applicable laws and limitations, individuals may exercise their rights concerning their personal information, including:\n\n'
        '• The right to be informed about the processing of their information.\n'
        '• The right to access their personal information.\n'
        '• The right to request correction of inaccurate or incomplete information.\n'
        '• The right to object to certain processing activities.\n'
        '• The right to request erasure or blocking when legally applicable.\n'
        '• The right to data portability when applicable.\n'
        '• The right to file a complaint with the appropriate authority.\n'
        '• The right to seek compensation for damages as provided by law.\n\n'
        'Requests may be submitted through the company\'s designated privacy contact. The company will verify the requester\'s identity and respond in accordance with applicable laws.',
  ),
  LegalSection(
    title: '8. Cookies and Technical Information',
    body:
        'If the web application uses cookies, device identifiers, or similar technologies, these may be used for necessary functions such as maintaining sessions, supporting security, or improving system operation.\n\n'
        'Any additional tracking technologies will be disclosed and managed in accordance with applicable requirements.',
  ),
  LegalSection(
    title: '9. Third-Party Services',
    body:
        'The system may use third-party services for authentication, database hosting, SMS delivery, email notifications, or online payment processing.\n\n'
        'Where applicable, these providers may process information necessary to perform their services. The company will take appropriate steps to ensure that such processing is governed by applicable agreements, privacy requirements, and security safeguards.',
  ),
  LegalSection(
    title: '10. Children\'s and Other Individuals\' Information',
    body:
        'The company will handle personal information relating to minors and other individuals who are not direct system users with particular care and in accordance with applicable laws.\n\n'
        'Information about relatives, connections, or other third parties must be collected only when necessary and through lawful means. Providing another person\'s information does not automatically authorize unrelated processing or disclosure.',
  ),
  LegalSection(
    title: '11. Changes to This Privacy Policy',
    body:
        'The company may update this Privacy Policy when its system, business processes, or legal obligations change.\n\n'
        'Material changes will be communicated through appropriate channels. Where required, the company will provide updated notices or obtain the necessary consent before implementing new processing activities.',
  ),
  LegalSection(
    title: '12. Contact Information and Privacy Concerns',
    body:
        'For questions, requests, or concerns about personal information and privacy, users may contact:\n\n'
        'Jireta Loans & Credit Corp.\n'
        'Sta. Barbara, Pangasinan\n'
        'Privacy Contact / Data Protection Officer: [Insert Name or Designated Contact]\n'
        'Official Email Address: [Insert Official Company Email]\n'
        'Contact Number: [Insert Official Company Contact Number]',
  ),
  LegalSection(
    title: '13. Acknowledgment',
    body:
        'By acknowledging this Privacy Policy, I confirm that I have been informed about how Jireta Loans & Credit Corp. may collect, use, store, and disclose my personal information for the purposes described above.\n\n'
        'I understand that this acknowledgment does not remove my rights under applicable data privacy laws and does not automatically authorize processing for unrelated purposes.',
  ),
  LegalSection(
    title: 'Jireta Loans & Credit Corp.',
    body: 'Sta. Barbara, Pangasinan',
  ),
];

/// Buksan ang Terms & Conditions sa scrollable na bottom sheet (hindi umaalis
/// sa kasalukuyang screen).
void showTermsAndConditionsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const LegalInfoSheet(
      title: 'Terms & Conditions',
      sections: kTermsAndConditionsSections,
    ),
  );
}

/// Buksan ang loan-confirmation Terms and Conditions sa scrollable na bottom
/// sheet — ito ang T&C ng loan application (bago ang "Submit Application").
void showLoanConfirmationTermsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const LegalInfoSheet(
      title: 'Terms & Conditions',
      sections: kLoanConfirmationTermsSections,
    ),
  );
}

/// Buksan ang Privacy Policy sa scrollable na bottom sheet.
void showPrivacyPolicySheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const LegalInfoSheet(
      title: 'Privacy Policy',
      sections: kPrivacyPolicySections,
    ),
  );
}

/// A row of tappable "Terms & Conditions" and "Privacy Policy" links used on
/// light-background screens. Tapping either link opens a bottom sheet with the
/// full legal content.
class LegalLinks extends StatelessWidget {
  const LegalLinks({
    super.key,
    this.textColor = AppColors.textSecondary,
    this.privacyUsesRoute = false,
    this.termsUsesRoute = false,
  });

  final Color textColor;

  /// `true` → ang "Privacy Policy" ay bubukas ng PUBLIC page
  /// (`/privacy-policy`) na may sariling URL, imbes na bottom sheet. Ito ang
  /// gamit sa login page (kailangan din ito ng Google OAuth verification).
  final bool privacyUsesRoute;

  /// `true` → ang "Terms & Conditions" ay bubukas ng PUBLIC page (`/terms`)
  /// imbes na bottom sheet. Default na sheet sa loob ng app para hindi
  /// mawala ang user sa screen niya.
  final bool termsUsesRoute;

  void _showTerms(BuildContext context) => showTermsAndConditionsSheet(context);

  void _showPrivacy(BuildContext context) => showPrivacyPolicySheet(context);

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

    /// Sheet sa loob ng app, o public page kapag naka-`true` ang flag.
    VoidCallback target(VoidCallback sheet, String route, bool useRoute) =>
        useRoute ? () => context.go(route) : sheet;

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        link(
            'Terms & Conditions',
            target(() => _showTerms(context), RouteConstants.termsAndConditions,
                termsUsesRoute)),
        Text(
          '·',
          style: TextStyle(fontSize: 12, color: textColor),
        ),
        link(
            'Privacy Policy',
            target(() => _showPrivacy(context), RouteConstants.privacyPolicy,
                privacyUsesRoute)),
      ],
    );
  }
}
