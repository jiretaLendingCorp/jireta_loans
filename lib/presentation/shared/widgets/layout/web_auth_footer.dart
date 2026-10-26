// lib/presentation/shared/widgets/layout/web_auth_footer.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';

/// Premium footer — keeps Explore & Contact as requested, no logo/brand,
/// no Privacy/Terms at bottom (copyright only, centered), compact height
/// so it never covers the login card.
class WebAuthFooter extends StatefulWidget {
  const WebAuthFooter({super.key});

  @override
  State<WebAuthFooter> createState() => _WebAuthFooterState();
}

class _WebAuthFooterState extends State<WebAuthFooter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 760;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(color: AppColors.deepNavy),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // gold accent top line
              Container(
                height: 2,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFC9A84C), Color(0xFFAD8A2E), Color(0xFFC9A84C)],
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 20 : 24,
                      vertical: isCompact ? 20 : 22,
                    ),
                    child: isCompact
                        ? const _CompactFooter()
                        : const _WideFooter(),
                  ),
                ),
              ),
              // bottom bar — copyright only, centered
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
                ),
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      '© 2026 Jireta Loans & Credit Corp 1966. All rights reserved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideFooter extends StatelessWidget {
  const _WideFooter();
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Explore', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.white)),
              const SizedBox(height: 14),
              // Tanging ang may TOTOONG nilalaman (Privacy Policy at Terms &
              // Conditions) ang nananatili. Ang mga placeholder na
              // ("About Us", "Help Center") ay inalis — dating nagpapakita ang
              // mga iyon ng "— coming soon" na snackbar. Inutos ng user:
              // WALANG "Coming Soon" sa landing page.
              //
              // Sariling URI ang dalawa (`/privacy-policy`,
              // `/terms-and-conditions`) — hindi bottom sheet — para may
              // totoong address na maibabahagi/bookmark at magamit sa Google
              // OAuth verification. Pareho ito ng ginagawa ng mga link sa
              // login page (`LegalLinks`).
              _FooterLink(
                label: 'Privacy Policy',
                onTap: () => context.go(RouteConstants.privacyPolicy),
              ),
              _FooterLink(
                label: 'Terms & Conditions',
                onTap: () => context.go(RouteConstants.termsAndConditions),
              ),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Contact', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.white)),
              const SizedBox(height: 14),
              const _ContactLine(icon: Icons.location_on_outlined, text: 'Jireta Loans & Credit Corp, Philippines'),
              const SizedBox(height: 10),
              const _ContactLine(icon: Icons.mail_outline_rounded, text: 'support@jireta.com'),
              const SizedBox(height: 10),
              const _ContactLine(icon: Icons.phone_outlined, text: '(02) 8XXX-XXXX'),
              const SizedBox(height: 12),
              Text('Mon–Fri 8:00 AM – 5:00 PM', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55))),
            ],
          ),
        ),
      ],
    );
  }

}

class _CompactFooter extends StatelessWidget {
  const _CompactFooter();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Explore', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.white)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14, runSpacing: 8,
          children: [
            // Placeholder na "Help Center" / "About Us" ay inalis — dating may
            // "— coming soon" na snackbar ang mga iyon.
            //
            // Parehong URI ng wide footer: dati'y `onTap: null` ito (patay na
            // link sa maliit na screen), kaya walang nangyayari sa mobile web.
            _FooterLink(
              label: 'Privacy Policy',
              onTap: () => context.go(RouteConstants.privacyPolicy),
            ),
            _FooterLink(
              label: 'Terms & Conditions',
              onTap: () => context.go(RouteConstants.termsAndConditions),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('Contact', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.white)),
        const SizedBox(height: 10),
        const _ContactLine(icon: Icons.mail_outline_rounded, text: 'support@jireta.com'),
        const SizedBox(height: 8),
        const _ContactLine(icon: Icons.phone_outlined, text: '(02) 8XXX-XXXX'),
        const SizedBox(height: 8),
        const _ContactLine(icon: Icons.location_on_outlined, text: 'Jireta Loans & Credit Corp'),
      ],
    );
  }
}

class _FooterLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _FooterLink({required this.label, required this.onTap});
  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 140),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _hovered ? AppColors.gold : Colors.white.withValues(alpha: 0.75)),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class _ContactLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContactLine({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.55)),
        const SizedBox(width: 8),
        // ignore: prefer_const_constructors
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.white, fontWeight: FontWeight.w400))),
      ],
    );
  }
}
