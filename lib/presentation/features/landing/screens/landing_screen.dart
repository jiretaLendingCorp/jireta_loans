// lib/presentation/features/landing/screens/landing_screen.dart
//
// PUBLIC landing page — the marketing / entry page shown BEFORE authentication.
//
// Composition: a dark backdrop holds the laptop-framed hero (navigation,
// headline, CTAs and the device stage), then the page continues on a light
// canvas with the product sections, closing with the final CTA and footer.
//
// This screen is intentionally self-contained and read-only:
//   • it never reads auth state, loan data or any account-scoped provider
//   • every figure shown is fictional demo data (see the mockup widgets)
//   • "Sign In" / "Get Started" only hand off to the existing auth routes
//
// The router owns the auth redirects, so a signed-in visitor never stays here.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_constants.dart';
import '../../../shared/widgets/layout/web_auth_footer.dart';
import '../../../shared/widgets/layout/web_auth_header.dart';
import '../widgets/landing_hero.dart';
import '../widgets/landing_nav_bar.dart';
import '../widgets/landing_sections.dart';
import '../widgets/landing_shared.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  /// Section order doubles as the navigation order.
  static const List<String> _labels = [
    'Home',
    'Features',
    'How It Works',
    'About',
  ];

  final ScrollController _scroll = ScrollController();

  /// Bumped once per scrolled frame so [LandingReveal] widgets can check
  /// whether they entered the viewport.
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  final List<GlobalKey> _sectionKeys =
      List<GlobalKey>.generate(4, (_) => GlobalKey());

  int _activeIndex = 0;
  bool _menuOpen = false;
  bool _tickScheduled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _tick.dispose();
    super.dispose();
  }

  // ── Account hand-off ─────────────────────────────────────────────────────

  /// Both destinations already exist and belong to the current auth flow.
  void _goSignIn() {
    context.go(kIsWeb ? RouteConstants.webLogin : RouteConstants.mobileLogin);
  }

  void _goGetStarted() {
    // Registration lives on the web workspace; the mobile app hands off to its
    // existing OTP entry point instead.
    context.go(kIsWeb ? RouteConstants.webRegister : RouteConstants.mobileLogin);
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void _selectSection(int index) {
    if (_menuOpen) setState(() => _menuOpen = false);
    final context = _sectionKeys[index].currentContext;
    if (context == null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;

    final absoluteTop = box.localToGlobal(Offset.zero).dy + _scroll.offset;
    final target = (absoluteTop - LandingBreakpoints.navHeight)
        .clamp(0.0, _scroll.position.maxScrollExtent);

    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 640),
      curve: Curves.easeInOutCubic,
    );
  }

  // ── Scroll handling ──────────────────────────────────────────────────────

  /// Defers the reveal tick to the end of the frame: scroll listeners can run
  /// during layout, and [LandingReveal] must not start an animation there.
  void _scheduleTick() {
    if (_tickScheduled) return;
    _tickScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tickScheduled = false;
      if (mounted) _tick.value = _tick.value + 1;
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final active = _resolveActiveSection();
    if (active != _activeIndex) setState(() => _activeIndex = active);
    _scheduleTick();
  }

  int _resolveActiveSection() {
    const threshold = LandingBreakpoints.navHeight + 120;
    var active = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final context = _sectionKeys[i].currentContext;
      if (context == null) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      if (box.localToGlobal(Offset.zero).dy <= threshold) active = i;
    }
    return active;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: LandingPalette.canvas,
        body: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _scheduleTick();
            return false;
          },
          child: LandingScrollScope(
            tick: _tick,
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // ── Dark hero region (navigation lives inside the frame) ──
                  // Keyed so the "Home" link resolves to the top of the page.
                  KeyedSubtree(
                    key: _sectionKeys[0],
                    child: LandingLaptopHero(
                      nav: _buildNav(),
                      onGetStarted: _goGetStarted,
                      onSignIn: _goSignIn,
                    ),
                  ),

                  // ── Light content region ──
                  ColoredBox(
                    color: LandingPalette.canvas,
                    child: Column(
                      children: [
                        const SizedBox(height: 34),
                        const LandingTrustBar(),
                        const SizedBox(height: 34),
                        _featuresSection(),
                        _howItWorksSection(),
                        const LandingDevicesSection(),
                        _aboutSection(),
                        _finalCtaSection(),
                      ],
                    ),
                  ),

                  // Same footer as every other public screen.
                  const WebAuthFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNav() {
    return Column(
      children: [
        // The app's own public header — identical to the sign-in screen, only
        // pointed at this page's sections.
        WebAuthHeader(
          navItems: [
            for (var i = 0; i < _labels.length; i++)
              WebAuthNavItem(
                label: _labels[i],
                isActive: _activeIndex == i,
                onTap: () => _selectSection(i),
              ),
          ],
          showSignInAction: true,
          registerLabel: 'Get Started',
          onCompactMenuTap: () => setState(() => _menuOpen = !_menuOpen),
          compactMenuOpen: _menuOpen,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _menuOpen
              ? LandingMobileMenu(
                  labels: _labels,
                  activeIndex: _activeIndex,
                  onSelect: _selectSection,
                  onSignIn: _goSignIn,
                  onGetStarted: _goGetStarted,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  // ── Sections ─────────────────────────────────────────────────────────────

  Widget _featuresSection() {
    return KeyedSubtree(
      key: _sectionKeys[1],
      child: Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 78),
        child: const LandingFeaturesSection(),
      ),
    );
  }

  Widget _howItWorksSection() {
    return Padding(
      key: _sectionKeys[2],
      padding: const EdgeInsets.fromLTRB(0, 78, 0, 72),
      child: const LandingHowItWorksSection(),
    );
  }

  Widget _aboutSection() {
    // White band, like the features section — otherwise About and the closing
    // CTA sit on the same canvas colour and read as one long block.
    return Container(
      key: _sectionKeys[3],
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 78),
      child: const LandingAboutSection(),
    );
  }

  Widget _finalCtaSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 84),
      child: LandingFinalCta(
        onGetStarted: _goGetStarted,
        onSignIn: _goSignIn,
      ),
    );
  }
}
