// lib/presentation/shared/widgets/layout/web_auth_header.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';

/// Premium, modern header for unauthenticated web screens.
///
/// Clean white surface with subtle shadow, animated entrance, hover
/// interactions, and no secured / shield badges.
class WebAuthHeader extends StatefulWidget {
  final bool showRegisterAction;
  const WebAuthHeader({super.key, this.showRegisterAction = true});

  @override
  State<WebAuthHeader> createState() => _WebAuthHeaderState();
}

class _WebAuthHeaderState extends State<WebAuthHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, -0.14), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 640;
    final isMedium = width >= 640 && width < 860;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          height: 68,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(
              bottom: BorderSide(color: Color(0xFFE9E9EE), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepNavy.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 24),
                child: Row(
                  children: [
                    _BrandLockup(isCompact: isCompact),
                    const Spacer(),
                    if (!isCompact && !isMedium) ...[
                      _NavLink(label: 'About', onTap: () => _showComingSoon(context)),
                      const SizedBox(width: 4),
                      _NavLink(label: 'Support', onTap: () => _showSupportSheet(context)),
                      const SizedBox(width: 4),
                      _NavLink(label: 'Contact', onTap: () => _showContactSheet(context)),
                      const SizedBox(width: 16),
                      _CtaButton(showRegister: widget.showRegisterAction),
                    ] else if (isMedium) ...[
                      _NavLink(label: 'Support', onTap: () => _showSupportSheet(context)),
                      const SizedBox(width: 12),
                      _CtaButton(showRegister: widget.showRegisterAction, compact: true),
                    ] else ...[
                      // compact: only CTA
                      if (widget.showRegisterAction) _CompactCta(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('About page — coming soon'),
        backgroundColor: AppColors.deepNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSupportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFE8E8EE), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Support', style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deepNavy)),
            const SizedBox(height: 8),
            const Text('For staff assistance, please contact your administrator or head manager. For technical issues, reach us at support@jireta.com.', style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.deepNavy, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContactSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFE8E8EE), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Contact Us', style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deepNavy)),
            const SizedBox(height: 12),
            const _ContactRow(icon: Icons.location_on_outlined, text: 'Jireta Loans & Credit Corp, Philippines'),
            const SizedBox(height: 10),
            const _ContactRow(icon: Icons.mail_outline_rounded, text: 'support@jireta.com'),
            const SizedBox(height: 10),
            const _ContactRow(icon: Icons.phone_outlined, text: '(02) 8XXX-XXXX'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.deepNavy, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContactRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
          child: Icon(icon, size: 16, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
      ],
    );
  }
}

class _BrandLockup extends StatelessWidget {
  final bool isCompact;
  const _BrandLockup({required this.isCompact});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo with soft shadow — premium
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.95), width: 1.6),
            boxShadow: [
              BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            AssetConstants.logoJpg,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_rounded, color: AppColors.deepNavy, size: 18),
          ),
        ),
        const SizedBox(width: 11),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'JIRETA',
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.deepNavy,
                letterSpacing: 2.4,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 14, height: 1.2, color: AppColors.gold.withValues(alpha: 0.9)),
                const SizedBox(width: 6),
                Text(
                  isCompact ? 'LOANS & CREDIT · 1966' : 'LOANS & CREDIT CORP · 1966',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 1.35),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _NavLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _NavLink({required this.label, required this.onTap});
  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.deepNavy.withValues(alpha: 0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _hovered ? AppColors.deepNavy : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 2,
                width: _hovered ? 16 : 0,
                decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CtaButton extends StatefulWidget {
  final bool showRegister;
  final bool compact;
  const _CtaButton({required this.showRegister, this.compact = false});
  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    if (!widget.showRegister) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: OutlinedButton(
            onPressed: () => context.go(RouteConstants.webLogin),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.deepNavy,
              side: const BorderSide(color: AppColors.deepNavy, width: 1.4),
              padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Sign in', style: TextStyle(fontSize: widget.compact ? 12.5 : 13, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: AppColors.deepNavy,
            borderRadius: BorderRadius.circular(10),
            boxShadow: _hovered
                ? [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.20), blurRadius: 14, offset: const Offset(0, 6))]
                : [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: ElevatedButton(
            onPressed: () => context.go(RouteConstants.webRegister),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: widget.compact ? 16 : 20, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Sign up', style: TextStyle(fontSize: widget.compact ? 12.5 : 13, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
          ),
        ),
      ),
    );
  }
}

class _CompactCta extends StatefulWidget {
  @override
  State<_CompactCta> createState() => _CompactCtaState();
}

class _CompactCtaState extends State<_CompactCta> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.deepNavy : AppColors.deepNavy.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextButton(
          onPressed: () => context.go(RouteConstants.webRegister),
          style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          child: const Text('Sign up', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
