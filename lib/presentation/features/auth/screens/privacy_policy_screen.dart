// lib/presentation/features/auth/screens/privacy_policy_screen.dart
//
// PUBLIC na Privacy Policy page (`/privacy-policy`).
//
// BAKIT: kinakailangan ng Google OAuth verification ang isang public na
// privacy-policy URL, at kailangan din ito ng mga external na link. Ang design
// at nilalaman ay pareho ng Terms page (tingnan ang [LegalDocumentPage]),
// at isang pinagmumulan lang ang text: `kPrivacyPolicySections`.
import 'package:flutter/material.dart';

import '../../../shared/widgets/legal_document_page.dart';
import '../../../shared/widgets/legal_links.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentPage(
      title: 'Privacy Policy',
      intro:
          'How Jireta Loans & Credit Corp. collects, uses, and protects your '
          'personal information — in accordance with the Data Privacy Act of '
          '2012 (RA 10173).',
      sections: kPrivacyPolicySections,
    );
  }
}
