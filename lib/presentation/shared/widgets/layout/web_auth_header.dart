// lib/presentation/shared/widgets/layout/web_auth_header.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';

/// A single link in the [WebAuthHeader] navigation.
///
/// Pass a list of these through [WebAuthHeader.navItems] when a page needs its
/// own section links (the public landing page, for example). Leaving
/// [WebAuthHeader.navItems] null keeps the default Support / Contact set, so
/// the sign-in and registration screens are unaffected.
class WebAuthNavItem {
  final String label;
  final VoidCallback? onTap;

  /// Draws the gold pill + dot permanently — used for the section the visitor
  /// is currently reading.
  final bool isActive;

  const WebAuthNavItem({
    required this.label,
    this.onTap,
    this.isActive = false,
  });
}

/// Premium, modern header for unauthenticated web screens.
///
/// Clean light surface with a gold accent hairline, animated entrance, hover
/// interactions, and no secured / shield badges. One component serves every
/// public screen — sign in, registration and the landing page.
///
/// Pages that supply their own [navItems] (the landing page) additionally get
/// the slim utility ribbon above the brand row; auth screens keep the plain
/// bar so they stay focused on the form.
class WebAuthHeader extends StatefulWidget {
  final bool showRegisterAction;

  /// Renders the outlined sign-in button ahead of the primary CTA.
  final bool showSignInAction;

  /// Text of the primary (filled) CTA.
  final String registerLabel;

  /// Text of the outlined sign-in button.
  final String signInLabel;

  /// Section links. Null keeps the default Support / Contact links.
  final List<WebAuthNavItem>? navItems;

  /// Below 860px a menu button replaces the links; the page renders its own
  /// panel beneath the header when the callback fires.
  final VoidCallback? onCompactMenuTap;
  final bool compactMenuOpen;

  /// Tapping the brand lockup. The landing page uses it to glide back to the
  /// top of the page; null keeps the lockup inert.
  final VoidCallback? onBrandTap;

  const WebAuthHeader({
    super.key,
    this.showRegisterAction = true,
    this.showSignInAction = false,
    this.registerLabel = 'Sign up',
    this.signInLabel = 'Sign in',
    this.navItems,
    this.onCompactMenuTap,
    this.compactMenuOpen = false,
    this.onBrandTap,
  });

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
    final items = widget.navItems;

    // Pages that bring their own section links get the marketing chrome.
    final landing = items != null;

    // Narrow layouts swap the section links for a menu button.
    final menuButton = landing && widget.onCompactMenuTap != null
        ? _CompactMenuButton(
            open: widget.compactMenuOpen,
            onTap: widget.onCompactMenuTap!,
          )
        : null;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (landing)
              _HeaderRibbon(onContact: () => _showContactSheet(context)),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Color(0xFFFBFCFE)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepNavy.withValues(alpha: 0.055),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 68,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1160),
                        child: Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: isCompact ? 16 : 24),
                          child: Row(
                            children: [
                              _BrandLockup(
                                isCompact: isCompact,
                                onTap: widget.onBrandTap,
                              ),
                              const Spacer(),
                              if (!isCompact && !isMedium) ...[
                                if (items != null)
                                  for (final item in items) ...[
                                    _NavLink(
                                      label: item.label,
                                      active: item.isActive,
                                      onTap: item.onTap ?? () {},
                                    ),
                                    const SizedBox(width: 4),
                                  ]
                                else ...[
                                  // Ang "About" (placeholder na nagpapakita ng
                                  // "— coming soon") ay inalis — inutos ng user
                                  // na WALANG "Coming Soon" sa public na web
                                  // pages.
                                  _NavLink(
                                      label: 'Support',
                                      onTap: () => _showSupportSheet(context)),
                                  const SizedBox(width: 4),
                                  _NavLink(
                                      label: 'Contact',
                                      onTap: () => _showContactSheet(context)),
                                ],
                                const SizedBox(width: 16),
                                if (widget.showSignInAction) ...[
                                  _CtaButton(
                                    showRegister: false,
                                    label: widget.signInLabel,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                if (widget.showRegisterAction)
                                  _CtaButton(
                                    showRegister: true,
                                    label: widget.registerLabel,
                                    rich: landing,
                                  ),
                              ] else if (isMedium) ...[
                                if (items == null) ...[
                                  _NavLink(
                                      label: 'Support',
                                      onTap: () => _showSupportSheet(context)),
                                  const SizedBox(width: 12),
                                ],
                                if (widget.showSignInAction) ...[
                                  _CtaButton(
                                    showRegister: false,
                                    label: widget.signInLabel,
                                    compact: true,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (widget.showRegisterAction)
                                  _CtaButton(
                                    showRegister: true,
                                    label: widget.registerLabel,
                                    compact: true,
                                    rich: landing,
                                  ),
                                if (menuButton != null) ...[
                                  const SizedBox(width: 8),
                                  menuButton,
                                ],
                              ] else if (menuButton != null) ...[
                                // compact, page-managed links: the menu carries
                                // the CTAs, so the bar only needs the button.
                                menuButton,
                              ] else ...[
                                // compact: only CTA
                                if (widget.showRegisterAction)
                                  _CompactCta(label: widget.registerLabel),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Definition line + centered gold accent — replaces the old
                  // flat grey border.
                  Container(height: 1, color: const Color(0xFFEDEFF4)),
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.gold.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Utility ribbon (landing only)
// ─────────────────────────────────────────────────────────────────────────────

/// Slim navy strip above the brand row.
///
/// Marketing chrome: it states the regulated-lending trust line and gives the
/// public site a one-tap route to the support/contact sheet. Auth screens skip
/// it entirely, so they keep a single focused bar.
class _HeaderRibbon extends StatelessWidget {
  final VoidCallback onContact;

  const _HeaderRibbon({required this.onContact});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final showPhone = width >= 1024;

    return Container(
      width: double.infinity,
      height: 34,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF08111C), Color(0xFF14304F), Color(0xFF08111C)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  size: 13,
                  color: AppColors.goldLight,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    compact
                        ? 'Trusted since 1966 · SEC-registered'
                        : 'SEC-registered lending corporation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Color(0xFFD7DEE8),
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 14),
                  Text(
                    'Trusted since 1966',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Colors.white.withValues(alpha: 0.52),
                    ),
                  ),
                  const Spacer(),
                  _RibbonAction(
                    icon: Icons.mail_outline_rounded,
                    label: 'support@jireta.com',
                    onTap: onContact,
                  ),
                  if (showPhone) ...[
                    const SizedBox(width: 16),
                    _RibbonAction(
                      icon: Icons.phone_outlined,
                      label: '(02) 8XXX-XXXX',
                      onTap: onContact,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RibbonAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RibbonAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_RibbonAction> createState() => _RibbonActionState();
}

class _RibbonActionState extends State<_RibbonAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: _hovered ? 1 : 0.8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 12.5, color: AppColors.goldLight),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: Color(0xFFD7DEE8),
                ),
              ),
            ],
          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Brand lockup
// ─────────────────────────────────────────────────────────────────────────────

class _BrandLockup extends StatefulWidget {
  final bool isCompact;
  final VoidCallback? onTap;

  const _BrandLockup({required this.isCompact, this.onTap});

  @override
  State<_BrandLockup> createState() => _BrandLockupState();
}

class _BrandLockupState extends State<_BrandLockup> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;

    return MouseRegion(
      cursor:
          onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: onTap == null ? null : (_) => setState(() => _hovered = true),
      onExit: onTap == null ? null : (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gold gradient ring with the logo inside — premium brand mark.
            AnimatedScale(
              scale: _hovered ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(1.7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.goldLight,
                      AppColors.gold,
                      AppColors.goldDark,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.deepNavy
                          .withValues(alpha: _hovered ? 0.16 : 0.08),
                      blurRadius: _hovered ? 14 : 10,
                      offset: const Offset(0, 3),
                    ),
                    BoxShadow(
                      color: AppColors.gold
                          .withValues(alpha: _hovered ? 0.32 : 0.14),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    AssetConstants.logoJpg,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.account_balance_rounded,
                      color: AppColors.deepNavy,
                      size: 17,
                    ),
                  ),
                ),
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
                // Ang gintong "——" na linya sa unahan ng subtitle ay inalis
                // (inutos ng user) — ang teksto na lang ang natitira sa ilalim
                // ng "JIRETA".
                Text(
                  widget.isCompact
                      ? 'LOANS & CREDIT · 1966'
                      : 'LOANS & CREDIT CORP · 1966',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.35,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navigation link
// ─────────────────────────────────────────────────────────────────────────────

class _NavLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _NavLink({
    required this.label,
    required this.onTap,
    this.active = false,
  });
  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final highlighted = _hovered || active;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? AppColors.gold.withValues(alpha: 0.12)
                : (_hovered
                    ? AppColors.deepNavy.withValues(alpha: 0.055)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? AppColors.gold.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gold status dot — grows in on hover / while the section is
              // active, replacing the old static underline.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: highlighted ? 6 : 0,
                height: 6,
                margin: EdgeInsets.only(right: highlighted ? 7 : 0),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                  boxShadow: highlighted
                      ? [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color:
                      highlighted ? AppColors.deepNavy : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CTAs
// ─────────────────────────────────────────────────────────────────────────────

class _CtaButton extends StatefulWidget {
  final bool showRegister;
  final bool compact;
  final String? label;

  /// Landing chrome: adds the arrow that slides on hover to the filled CTA.
  final bool rich;

  const _CtaButton({
    required this.showRegister,
    this.compact = false,
    this.label,
    this.rich = false,
  });
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
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _hovered ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppColors.deepNavy.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovered
                    ? AppColors.gold
                    : AppColors.deepNavy.withValues(alpha: 0.4),
                width: 1.4,
              ),
            ),
            child: OutlinedButton(
              onPressed: () => context.go(RouteConstants.webLogin),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepNavy,
                side: BorderSide.none,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 14 : 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                widget.label ?? 'Sign in',
                style: TextStyle(
                  fontSize: widget.compact ? 12.5 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            // Navy gradient fill + gold glow on hover.
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF17304E), AppColors.deepNavy],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: AppColors.deepNavy.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: AppColors.deepNavy.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: ElevatedButton(
            onPressed: () => context.go(RouteConstants.webRegister),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 16 : 20,
                vertical: 11,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label ?? 'Sign up',
                  style: TextStyle(
                    fontSize: widget.compact ? 12.5 : 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
                if (widget.rich) ...[
                  const SizedBox(width: 6),
                  AnimatedSlide(
                    offset: _hovered ? const Offset(0.2, 0) : Offset.zero,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.arrow_forward_rounded, size: 15),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactCta extends StatefulWidget {
  final String? label;
  const _CompactCta({this.label});
  @override
  State<_CompactCta> createState() => _CompactCtaState();
}

/// Menu button shown below the tablet breakpoint when the page supplies its
/// own section links. The icon rotates between the hamburger and the close
/// cross instead of swapping instantly.
class _CompactMenuButton extends StatefulWidget {
  final bool open;
  final VoidCallback onTap;

  const _CompactMenuButton({required this.open, required this.onTap});

  @override
  State<_CompactMenuButton> createState() => _CompactMenuButtonState();
}

class _CompactMenuButtonState extends State<_CompactMenuButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.open ? 'Close menu' : 'Open menu',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.open || _hovered
                  ? AppColors.deepNavy.withValues(alpha: 0.06)
                  : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovered
                    ? AppColors.gold.withValues(alpha: 0.6)
                    : const Color(0xFFE9E9EE),
              ),
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: Tween<double>(begin: 0.72, end: 1).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  widget.open ? Icons.close_rounded : Icons.menu_rounded,
                  key: ValueKey<bool>(widget.open),
                  size: 20,
                  color: AppColors.deepNavy,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
          child: Text(widget.label ?? 'Sign up', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
