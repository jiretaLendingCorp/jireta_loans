// lib/presentation/shared/widgets/legal_document_page.dart
//
// PUBLIC na legal page (Privacy Policy / Terms & Conditions) — isang design
// para sa dalawa: brand header + card + mga section + footer.
//
// Walang login at walang backend call: purong static content mula sa
// `legal_links.dart`, kaya bukas ito kahit hindi pa naka-sign in at may
// sariling URL (`/privacy-policy`, `/terms-and-conditions`) na puwedeng
// gamitin sa Google OAuth verification at sa mga external na link.
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../features/lender/profile/screens/widgets/legal_info_sheet.dart';

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.intro,
    required this.sections,
  });

  /// Pamagat sa loob ng card, hal. `Privacy Policy`.
  final String title;

  /// Isang maikling paliwanag sa ilalim ng pamagat.
  final String intro;

  /// Nilalaman — galing sa `kPrivacyPolicySections` /
  /// `kTermsAndConditionsSections` (parehong text ng bottom sheet sa app).
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Brand ──
                  const Text(
                    'Jireta Loans',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.deepNavy,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '& CREDIT CORP 1966',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.6,
                      color: AppColors.goldDark,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Dokumento ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.deepNavy.withValues(alpha: 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepNavy,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          intro,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        for (final section in sections) ...[
                          Text(
                            section.title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.deepNavy,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Naka-hanging indent ang mga bullet at numbered
                          // na linya: kapag humaba at nag-wrap, nakapila pa
                          // rin ang teksto sa ilalim ng unang letra — hindi
                          // bumabalik sa kaliwang gilid ng card.
                          _LegalBody(section.body),
                          const SizedBox(height: 18),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Footer ──
                  Text(
                    '© 1966  Jireta Loans & Credit Corp',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary.withValues(alpha: 0.9),
                      letterSpacing: 0.4,
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

/// Katawan ng isang section: mga talata, bullet, at numbered na linya —
/// may tamang hanging indent.
///
/// BAKIT: dating isang `Text` lang ang buong body, kaya ang mga bullet na
/// `• Personal Information: ...` na nag-wrap ay bumabalik sa kaliwang gilid
/// (nakalabas ang ikalawang linya sa ilalim ng bullet mismo), at ang
/// `\n\n` ay nagiging isang buong blangkong linya na sobrang laki ng agwat.
/// Dito, ang marka (`•` / `1.`) ay may sariling kolum at ang teksto ay nasa
/// `Expanded` — kaya pantay ang pagkakahanay ng lahat ng sumunod na linya.
class _LegalBody extends StatelessWidget {
  const _LegalBody(this.body);

  final String body;

  static const TextStyle _style = TextStyle(
    fontSize: 13,
    height: 1.65,
    color: AppColors.textSecondary,
  );

  /// `1. Teksto`, `10. Teksto`
  static final RegExp _numbered = RegExp(r'^(\d+)\.\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    // Nakita ang blangkong linya → mas malaking agwat bago ang susunod na
    // talata; kung magkasunod na item lang, maliit na agwat para hindi
    // magmukhang magkahiwalay na grupo.
    var blankBefore = false;

    void add(Widget child) {
      if (blocks.isNotEmpty) {
        blocks.add(SizedBox(height: blankBefore ? 10 : 4));
      }
      blocks.add(child);
      blankBefore = false;
    }

    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        blankBefore = true;
        continue;
      }

      if (line.startsWith('• ')) {
        add(_LegalItem(marker: '•', text: line.substring(2), style: _style));
        continue;
      }

      final numbered = _numbered.firstMatch(line);
      if (numbered != null) {
        add(_LegalItem(
          marker: '${numbered.group(1)}.',
          text: numbered.group(2)!.trim(),
          style: _style,
        ));
        continue;
      }

      add(Text(line, style: _style));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}

/// Isang linyang may marka sa kaliwa (`•` o `1.`). Ang teksto ay nasa
/// [Expanded], kaya hawak nito ang hangganan at nag-wrap sa ilalim ng sarili
/// niya — ito ang nagbibigay ng hanging indent.
class _LegalItem extends StatelessWidget {
  const _LegalItem({
    required this.marker,
    required this.text,
    required this.style,
  });

  final String marker;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // Sapat na lapad para sa `10.` at sa `•` — pareho ang lapad ng kolum sa
    // lahat ng linya, kaya pantay ang simula ng teksto (hindi gumagalaw
    // pakanan kapag umabot sa 10+ ang bilang).
    final markerWidth = marker == '•' ? 14.0 : 26.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: markerWidth,
          // Isang linya lang palagi ang marka — kung hindi, puwedeng
          // mag-wrap ang `10.` at mabali ang pagkakahanay.
          child: Text(
            marker,
            style: style,
            maxLines: 1,
            softWrap: false,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
