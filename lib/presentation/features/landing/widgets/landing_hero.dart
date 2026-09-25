// lib/presentation/features/landing/widgets/landing_hero.dart
//
// Hero composition (public marketing page):
//
//   dark backdrop
//     └── laptop / browser frame            ← presentation shell (≥ desktop)
//           ├── navigation bar
//           ├── centered headline + CTAs
//           └── device stage: phone mockup + floating LMS cards + blob
//
// The framed content is laid out once on a fixed design canvas and scaled into
// the lid, so the composition (and the crop at the bottom edge, exactly like
// the reference) is identical at every desktop width.
//
// Below the desktop breakpoint the very same composition is rendered flat and
// fully responsive — no shrunken laptop on a phone.
//
// ⚠️ Every number shown by the device stage is FICTIONAL demo data.
import 'package:flutter/material.dart';

import 'landing_mockups.dart';
import 'landing_shared.dart';

/// Canvas the framed hero is designed on (inner width of the laptop lid).
const double _kDesignWidth = 1160;
const double _kDesignAspect = 16 / 10;

class LandingLaptopHero extends StatelessWidget {
  /// Site navigation. Renders INSIDE the frame, or as a plain top bar when
  /// the frame is dropped on smaller screens.
  final Widget nav;

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const LandingLaptopHero({
    super.key,
    required this.nav,
    required this.onGetStarted,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final framed = width >= LandingBreakpoints.desktop;
    final gutter = LandingBreakpoints.gutter(width);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        nav,
        _HeroCopy(
          onDark: !framed,
          onGetStarted: onGetStarted,
          onSignIn: onSignIn,
        ),
        _DevicePanel(framed: framed),
      ],
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF04080F), Color(0xFF09111C), Color(0xFF111D2E)],
        ),
      ),
      child: Stack(
        children: [
          // Ambient grid overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.25,
                child: CustomPaint(
                  painter: _HeroGridPainter(),
                ),
              ),
            ),
          ),
          // Indigo light pool behind the laptop, like the reference shot.
          const Positioned(
            bottom: -180,
            left: 0,
            right: 0,
            child: Center(
              child: LandingGlow(
                color: Color(0xFF3B5BDB),
                size: 820,
                alpha: 0.32,
              ),
            ),
          ),
          const Positioned(
            top: -60,
            right: -80,
            child: LandingGlow(
              color: LandingPalette.gold,
              size: 420,
              alpha: 0.12,
            ),
          ),
          const Positioned(
            top: 100,
            left: -100,
            child: LandingGlow(
              color: Color(0xFF0F9D8E),
              size: 380,
              alpha: 0.10,
            ),
          ),
          Padding(
            // Status-bar inset: the dark backdrop runs behind the system bars.
            padding: EdgeInsets.fromLTRB(
              framed ? gutter : 0,
              media.padding.top + (framed ? 30 : 0),
              framed ? gutter : 0,
              framed ? 64 : 40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: LandingBreakpoints.contentMaxWidth,
                ),
                child: framed ? _LaptopScreen(child: content) : content,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Laptop shell
// ─────────────────────────────────────────────────────────────────────────────

class _LaptopScreen extends StatelessWidget {
  final Widget child;

  const _LaptopScreen({required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF15171D),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.62),
                blurRadius: 70,
                offset: const Offset(0, 40),
              ),
              BoxShadow(
                color: const Color(0xFF3B3F8F).withValues(alpha: 0.22),
                blurRadius: 60,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: _kDesignAspect,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: _kDesignWidth,
                  height: _kDesignWidth / _kDesignAspect,
                  child: ClipRect(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: MediaQuery(
                        // Inside the lid the page is always laid out at the
                        // design width, so the composition never reflows.
                        data: MediaQuery.of(context).copyWith(
                          size: const Size(_kDesignWidth, 900),
                          padding: EdgeInsets.zero,
                          viewPadding: EdgeInsets.zero,
                        ),
                        // The lid renders the page on white, like a browser.
                        child: ColoredBox(
                          key: const ValueKey<String>('landing-frame-surface'),
                          color: Colors.white,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const _LaptopDeck(),
      ],
    );
  }
}

class _LaptopDeck extends StatelessWidget {
  const _LaptopDeck();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2B2E36), Color(0xFF121419)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Center(
        child: Container(
          width: 96,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Centered hero copy
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCopy extends StatelessWidget {
  final bool onDark;
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const _HeroCopy({
    required this.onDark,
    required this.onGetStarted,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width >= LandingBreakpoints.desktop
        ? 44.0
        : (width >= LandingBreakpoints.tablet ? 36.0 : 27.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        onDark ? 20 : 34,
        onDark ? 28 : 22,
        onDark ? 20 : 34,
        24,
      ),
      child: Column(
        children: [
          // Trust tag pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: onDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : LandingPalette.navy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: onDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : LandingPalette.line,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'NEXT-GEN MICROFINANCE PLATFORM',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: onDark ? LandingPalette.goldSoft : LandingPalette.navy,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Lending Management System',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: titleSize,
              height: 1.14,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              color: onDark ? Colors.white : const Color(0xFF0B1220),
            ),
          ),
          const SizedBox(height: 13),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              'Manage loan applications, approvals, payments, collections, and '
              'lending operations in one secure platform.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: width < LandingBreakpoints.tablet ? 14 : 15.5,
                height: 1.62,
                color: onDark
                    ? Colors.white.withValues(alpha: 0.70)
                    : LandingPalette.muted,
              ),
            ),
          ),
          const SizedBox(height: 22),
          _CtaCluster(onGetStarted: onGetStarted, onSignIn: onSignIn),
          const SizedBox(height: 13),
          Text(
            '*Register online in a few minutes — sign in any time to manage '
            'an existing account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: onDark
                  ? Colors.white.withValues(alpha: 0.46)
                  : LandingPalette.faint,
            ),
          ),
        ],
      ),
    );
  }
}

/// White CTA card echoing the reference's form row — holds the two real CTAs.
class _CtaCluster extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const _CtaCluster({required this.onGetStarted, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    final getStarted = LandingPrimaryButton(
      label: 'Get Started',
      trailingIcon: Icons.arrow_forward_rounded,
      onTap: onGetStarted,
    );
    final signIn = LandingGhostButton(label: 'Sign In', onTap: onSignIn);

    // The buttons keep their natural width — the card only hugs them. `Wrap`
    // then puts them on one row while both fit and drops the second one to its
    // own line on the narrowest phones, never stretching either one.
    return Container(
      key: const ValueKey<String>('landing-hero-cta'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LandingPalette.line),
        boxShadow: [
          BoxShadow(
            color: LandingPalette.navy.withValues(alpha: 0.10),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [getStarted, signIn],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Device stage
// ─────────────────────────────────────────────────────────────────────────────

class _DevicePanel extends StatelessWidget {
  final bool framed;

  const _DevicePanel({required this.framed});

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F6),
        borderRadius: framed ? BorderRadius.zero : BorderRadius.circular(22),
      ),
      padding: EdgeInsets.only(top: framed ? 34 : 28),
      child: const LandingDeviceStage(),
    );

    if (framed) return panel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: panel,
    );
  }
}

/// Phone mockup ringed by floating LMS cards. Transparent-top, dark-bottom:
/// the lower half is intentionally allowed to run past the frame edge.
class LandingDeviceStage extends StatelessWidget {
  const LandingDeviceStage({super.key});

  /// Device height ÷ width (design canvas 300 × 620).
  static const double _phoneRatio = 620 / 300;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 900.0;
        final framed = w >= 1000;

        final phoneW = framed ? 236.0 : (w * 0.54).clamp(146.0, 214.0);
        final phoneH = phoneW * _phoneRatio;
        const cardH = 88.0;
        // The green accent card carries three lines, so it gets extra height.
        const accentCardH = 96.0;
        final topMargin = framed ? 54.0 : 80.0;
        final boxH = phoneH + topMargin * 2;
        final phoneLeft = (w - phoneW) / 2;

        /// Absolute offset → Stack [Alignment] so the stage scales with the
        /// available width instead of relying on magic pixel values.
        double alignOf(double pos, double freeSpace) {
          if (freeSpace <= 0) return 0;
          return (2 * pos / freeSpace - 1).clamp(-1.0, 1.0);
        }

        double sideX({required bool left, required double childW}) {
          final overlap = framed ? 22.0 : 14.0;
          final x = left
              ? phoneLeft + overlap - childW
              : phoneLeft + phoneW - overlap;
          return alignOf(x, w - childW);
        }

        double sideY(double fraction, double childH) =>
            alignOf(topMargin + fraction * phoneH, boxH - childH);

        final cards = <Widget>[];

        void add(FloatCardSpec spec,
            {required Alignment alignment, int phase = 0}) {
          cards.add(
            Positioned.fill(
              child: Align(
                alignment: alignment,
                child: FloatCard(
                  key: ValueKey<String>('float-${spec.id}'),
                  spec: spec,
                  floatPhase: phase,
                ),
              ),
            ),
          );
        }

        if (!framed) {
          // ── Phones: two corner badges, never over the headline ──
          final cornerW = (w * 0.54).clamp(140.0, 200.0);
          add(
            FloatCardSpec(
              id: 'approved',
              width: cornerW,
              height: accentCardH,
              background: LandingPalette.green,
              borderColor: LandingPalette.green,
              build: _approvedCardBody,
            ),
            alignment: Alignment.topRight,
            phase: 1,
          );
          add(
            FloatCardSpec(
              id: 'progress',
              width: cornerW,
              height: cardH,
              build: _progressCardBody,
            ),
            alignment: Alignment.bottomLeft,
            phase: 3,
          );
        } else {
          const cardW = 186.0;
          final leftX = sideX(left: true, childW: cardW);
          final rightX = sideX(left: false, childW: cardW);

          // Left column.
          add(
            const FloatCardSpec(
              id: 'rider',
              width: cardW,
              height: 92,
              build: _riderCardBody,
            ),
            alignment: Alignment(leftX, sideY(0.0, 92)),
          );
          add(
            const FloatCardSpec(
              id: 'progress',
              width: cardW,
              height: cardH,
              build: _progressCardBody,
            ),
            alignment: Alignment(leftX, sideY(0.21, cardH)),
            phase: 2,
          );
          add(
            const FloatCardSpec(
              id: 'application',
              width: cardW,
              height: cardH,
              build: _applicationCardBody,
            ),
            alignment: Alignment(leftX, sideY(0.42, cardH)),
            phase: 4,
          );

          // Right column.
          add(
            const FloatCardSpec(
              id: 'approved',
              width: cardW,
              height: accentCardH,
              background: LandingPalette.green,
              borderColor: LandingPalette.green,
              build: _approvedCardBody,
            ),
            alignment: Alignment(rightX, sideY(0.03, accentCardH)),
            phase: 1,
          );
          add(
            const FloatCardSpec(
              id: 'payment',
              width: cardW,
              height: cardH,
              build: _paymentCardBody,
            ),
            alignment: Alignment(rightX, sideY(0.25, cardH)),
            phase: 3,
          );
          add(
            const FloatCardSpec(
              id: 'chart',
              width: cardW,
              height: 100,
              build: _chartCardBody,
            ),
            alignment: Alignment(rightX, sideY(0.47, 100)),
            phase: 5,
          );
        }

        return SizedBox(
          height: boxH,
          width: w,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Organic mass grounded behind the lower half of the device.
              Positioned(
                left: 0,
                right: 0,
                top: topMargin + phoneH * 0.30,
                height: boxH - (topMargin + phoneH * 0.30),
                child: const LandingBackdropBlob(),
              ),
              // Soft light behind the device.
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: phoneW * 1.35,
                    height: phoneW * 1.35,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          LandingPalette.accent.withValues(alpha: 0.10),
                          LandingPalette.accent.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Center(child: JiretaPhoneMockup(width: phoneW)),
              ),
              ...cards,
            ],
          ),
        );
      },
    );
  }
}

// Floating card bodies ───────────────────────────────────────────────────────

Widget _approvedCardBody() => const _GreenCard(
      title: 'Loan Approved',
      value: '₱20,000',
      subtitle: 'Funds released today',
    );

Widget _progressCardBody() => const FloatProgressBody();

Widget _paymentCardBody() => const FloatCardRow(
      icon: Icons.south_west_rounded,
      color: LandingPalette.accent,
      title: 'Payment Received',
      subtitle: 'GCash · Demo data',
      value: '₱2,500',
    );

Widget _applicationCardBody() => const FloatCardRow(
      icon: Icons.request_quote_outlined,
      color: LandingPalette.accent,
      title: 'Loan Application',
      subtitle: 'Under review',
    );

Widget _chartCardBody() => const FloatChartBody();

Widget _riderCardBody() => const _RiderCard();

/// Green "good news" card — the reference's high-contrast accent card.
class _GreenCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _GreenCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 13, color: Colors.white),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: Colors.white,
          ),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 8.5,
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
      ],
    );
  }
}

/// Rider card — field collections are part of the loop, not an afterthought.
class _RiderCard extends StatelessWidget {
  const _RiderCard();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.delivery_dining_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rider on the way',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: LandingPalette.ink,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Field collection · 2.1 km away',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: LandingPalette.faint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),          Positioned(
            right: -6,
            top: -6,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: LandingPalette.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child:
                  const Icon(Icons.check_rounded, size: 12, color: Colors.white),
            ),
          ),
        ],
      );
    }
  }

class _HeroGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    const gap = 48.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

