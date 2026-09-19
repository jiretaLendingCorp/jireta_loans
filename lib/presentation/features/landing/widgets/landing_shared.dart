// lib/presentation/features/landing/widgets/landing_shared.dart
//
// Shared building blocks for the PUBLIC landing page (marketing/entry page).
// Reuses the app's existing brand tokens (AppColors) and font families so the
// public site and the authenticated app look like one product.
//
// NOTE: Everything here is presentation-only. The landing page never reads
// auth state, loan data or any account-scoped provider.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Design tokens for the marketing page.
class LandingPalette {
  LandingPalette._();

  static const Color navy = AppColors.deepNavy; // #0D1B2A — brand primary
  static const Color navyDeep = Color(0xFF071018);
  static const Color navySoft = Color(0xFF1E3A5F);
  static const Color navyEdge = Color(0xFF14304F);

  /// Brighter product blue used for accents / charts on light surfaces.
  static const Color accent = Color(0xFF2F6FED);
  static const Color accentSoft = Color(0xFFE8F0FE);
  static const Color teal = Color(0xFF0F9D8E);

  static const Color gold = AppColors.gold;
  static const Color goldSoft = AppColors.goldLight;

  static const Color canvas = Color(0xFFF6F8FC);
  static const Color surface = Colors.white;
  static const Color line = Color(0xFFE6EAF2);
  static const Color ink = AppColors.textPrimary;
  static const Color muted = AppColors.textSecondary;
  static const Color faint = AppColors.textTertiary;

  static const Color green = AppColors.success;
  static const Color amber = AppColors.warning;

  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D1B2A), Color(0xFF1E3A5F), Color(0xFF0D1B2A)],
  );

  static List<BoxShadow> lift({
    double y = 16,
    double blur = 32,
    double alpha = 0.10,
  }) =>
      [
        BoxShadow(
          color: navy.withValues(alpha: alpha),
          blurRadius: blur,
          offset: Offset(0, y),
        ),
      ];

  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: navy.withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: navy.withValues(alpha: 0.03),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];
}

/// Breakpoints used across the landing page.
class LandingBreakpoints {
  LandingBreakpoints._();

  /// ≥ this width the hero shows the full two-column composition.
  static const double desktop = 1024;

  /// ≥ this width (and < desktop) tablet composition.
  static const double tablet = 720;

  static bool isDesktop(double w) => w >= desktop;
  static bool isTablet(double w) => w >= tablet && w < desktop;
  static bool isMobile(double w) => w < tablet;

  /// Horizontal page gutter for a given viewport width.
  static double gutter(double w) =>
      w >= desktop ? 40 : (w >= tablet ? 32 : 20);

  /// Max content width of each section.
  static const double contentMaxWidth = 1180;

  /// Height of the sticky navigation bar.
  static const double navHeight = 76;
}

/// Publishes a "the page scrolled" tick down to every [LandingReveal] so they
/// can each decide whether they entered the viewport. A single notifier beats
/// one scroll listener per animated widget.
class LandingScrollScope extends InheritedWidget {
  final Listenable tick;

  const LandingScrollScope({
    super.key,
    required this.tick,
    required super.child,
  });

  static Listenable? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LandingScrollScope>()
      ?.tick;

  @override
  bool updateShouldNotify(LandingScrollScope oldWidget) =>
      oldWidget.tick != tick;
}

/// Fades + lifts its child the first time it scrolls into view.
///
/// Degrades to "already visible" when the platform reports animations as
/// disabled, and never rebuilds the child while animating.
class LandingReveal extends StatefulWidget {
  final Widget child;

  /// Stagger position — later siblings reveal slightly after earlier ones.
  final int order;

  /// Distance in logical pixels the child travels while revealing.
  final double offsetY;

  final Duration duration;

  const LandingReveal({
    super.key,
    required this.child,
    this.order = 0,
    this.offsetY = 26,
    this.duration = const Duration(milliseconds: 620),
  });

  @override
  State<LandingReveal> createState() => _LandingRevealState();
}

class _LandingRevealState extends State<LandingReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;
  late final Animation<double> _t;
  Listenable? _tick;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _t = _curve;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = LandingScrollScope.maybeOf(context);
    if (!identical(tick, _tick)) {
      _tick?.removeListener(_measure);
      _tick = tick;
      _tick?.addListener(_measure);
    }
  }

  @override
  void dispose() {
    _tick?.removeListener(_measure);
    _curve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted || _triggered) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;

    final viewport = MediaQuery.sizeOf(context).height;
    final top = box.localToGlobal(Offset.zero).dy;

    // Reveal once the widget's top edge is comfortably inside the viewport.
    if (top > viewport * 0.92) return;

    _triggered = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _ctrl.value = 1;
      return;
    }
    final delay = Duration(milliseconds: 60 * widget.order.clamp(0, 6));
    if (delay == Duration.zero) {
      _ctrl.forward();
      return;
    }
    Future.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (_, child) {
        final v = _t.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - v) * widget.offsetY),
            child: child,
          ),
        );
      },
    );
  }
}

/// Centered, width-capped section content with responsive gutters.
class LandingContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double extraBottom;

  const LandingContainer({
    super.key,
    required this.child,
    this.maxWidth = LandingBreakpoints.contentMaxWidth,
    this.extraBottom = 0,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = LandingBreakpoints.gutter(width);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, extraBottom),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Small uppercase pill used above section titles.
class LandingEyebrow extends StatelessWidget {
  final String label;
  final bool onDark;

  const LandingEyebrow(this.label, {super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final bg = onDark
        ? Colors.white.withValues(alpha: 0.08)
        : LandingPalette.navy.withValues(alpha: 0.05);
    final fg = onDark ? LandingPalette.goldSoft : LandingPalette.navy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: onDark
              ? Colors.white.withValues(alpha: 0.12)
              : LandingPalette.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: onDark ? LandingPalette.gold : LandingPalette.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title block: eyebrow + headline + supporting paragraph.
class LandingSectionHeading extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final bool onDark;
  final bool center;
  final double titleSize;

  const LandingSectionHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.onDark = false,
    this.center = true,
    this.titleSize = 38,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final size = width < LandingBreakpoints.tablet ? 27.0 : titleSize;
    final align = center ? TextAlign.center : TextAlign.left;

    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        LandingEyebrow(eyebrow, onDark: onDark),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: align,
          style: TextStyle(
            fontSize: size,
            height: 1.16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.9,
            color: onDark ? Colors.white : LandingPalette.ink,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Text(
              subtitle!,
              textAlign: align,
              style: TextStyle(
                fontSize: width < LandingBreakpoints.tablet ? 14 : 15.5,
                height: 1.65,
                color: onDark
                    ? Colors.white.withValues(alpha: 0.72)
                    : LandingPalette.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Primary CTA — navy gradient with soft lift + hover scale.
class LandingPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? trailingIcon;
  final bool compact;
  final double minWidth;

  const LandingPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.trailingIcon,
    this.compact = false,
    this.minWidth = 0,
  });

  @override
  State<LandingPrimaryButton> createState() => _LandingPrimaryButtonState();
}

class _LandingPrimaryButtonState extends State<LandingPrimaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final double height = widget.compact ? 44 : 54;
    final double hPad = widget.compact ? 22 : 30;
    final lifted = _hovered || _pressed;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.975 : (_hovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: height,
            constraints: BoxConstraints(minWidth: widget.minWidth),
            padding: EdgeInsets.symmetric(horizontal: hPad),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LandingPalette.navyGradient,
              boxShadow: lifted
                  ? [
                      BoxShadow(
                        color: LandingPalette.navy.withValues(alpha: 0.30),
                        blurRadius: 26,
                        offset: const Offset(0, 14),
                      ),
                      BoxShadow(
                        color: LandingPalette.gold.withValues(alpha: 0.16),
                        blurRadius: 14,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: LandingPalette.navy.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.compact ? 14 : 15.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.1,
                  ),
                ),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: 10),
                  Transform.translate(
                    offset: Offset(_hovered ? 3 : 0, 0),
                    child: Icon(
                      widget.trailingIcon,
                      size: widget.compact ? 17 : 19,
                      color: Colors.white,
                    ),
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

/// Secondary CTA — outlined, tinted on hover.
class LandingGhostButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool compact;
  final bool onDark;

  const LandingGhostButton({
    super.key,
    required this.label,
    required this.onTap,
    this.compact = false,
    this.onDark = false,
  });

  @override
  State<LandingGhostButton> createState() => _LandingGhostButtonState();
}

class _LandingGhostButtonState extends State<LandingGhostButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final onDark = widget.onDark;
    final border = onDark
        ? Colors.white.withValues(alpha: 0.28)
        : LandingPalette.line;
    final fg = onDark ? Colors.white : LandingPalette.navy;
    final fill = onDark
        ? Colors.white.withValues(alpha: _hovered ? 0.12 : 0.04)
        : (_hovered ? LandingPalette.navy.withValues(alpha: 0.04) : Colors.white);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          height: widget.compact ? 44 : 54,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 22 : 30),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: _hovered && !onDark
                  ? LandingPalette.navy.withValues(alpha: 0.35)
                  : border,
              width: 1.2,
            ),
            boxShadow: onDark || !_hovered
                ? null
                : [
                    BoxShadow(
                      color: LandingPalette.navy.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          // `widthFactor: 1` keeps the label shrink-wrapped inside a Wrap (so
          // the CTAs stay on one row), yet centres it when the parent stretches
          // the button to full width — a plain Center would expand and force
          // the buttons to stack.
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: widget.compact ? 14 : 15.5,
                fontWeight: FontWeight.w700,
                color: fg,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft white surface used by most landing cards.
class LandingCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? shadow;
  final Gradient? gradient;

  const LandingCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 18,
    this.color,
    this.borderColor,
    this.shadow,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? LandingPalette.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? LandingPalette.line,
          width: 1,
        ),
        boxShadow: shadow ?? LandingPalette.cardShadow,
      ),
      child: child,
    );
  }
}

/// Icon in a tinted rounded square — used by feature/value cards.
class LandingIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const LandingIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.30),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.44, color: color),
    );
  }
}

/// Soft radial light pool used behind the hero composition.
class LandingGlow extends StatelessWidget {
  final Color color;
  final double size;
  final double alpha;

  const LandingGlow({
    super.key,
    required this.color,
    required this.size,
    required this.alpha,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
