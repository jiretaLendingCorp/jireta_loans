// lib/presentation/features/auth/screens/terms_of_service_screen.dart
//
// PUBLIC na Terms & Conditions page (`/terms-and-conditions`).
//
// KAPAREHO ng Privacy Policy page: sariling URL, walang login, at parehong
// design ([LegalDocumentPage]). Ito ang binubuksan ng "Terms & Conditions"
// link sa login page — imbes na bottom sheet — para may totoong address na
// maibabahagi (at para sa Google OAuth verification).
//
// HINDI ito kapareho ng [TermsConditionsScreen] (`/terms`): iyon ang
// one-time acceptance step PAGKATAPOS mag-login (may Continue/accept), ito
// naman ang pampublikong dokumento.
import 'package:flutter/material.dart';

import '../../../shared/widgets/legal_document_page.dart';
import '../../../shared/widgets/legal_links.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentPage(
      title: 'Terms & Conditions',
      intro:
          'The terms and conditions for using the Jireta Loans & Credit Corp. '
          'Web and Mobile-Based Digitized Lending Management System.',
      sections: kTermsAndConditionsSections,
    );
  }
}
