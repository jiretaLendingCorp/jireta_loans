// lib/presentation/features/landing/widgets/landing_mockups.dart
//
// Device + product mockups for the PUBLIC landing page.
//
// ⚠️ Every figure rendered here is FICTIONAL demo data. The visitor is not
// authenticated yet, so nothing on this page is fetched from the backend — no
// real borrower/lender records, balances, collections or portfolio figures.
import 'package:flutter/material.dart';

import '../../../../core/constants/asset_constants.dart';
import '../../../../core/theme/app_colors.dart';
import 'landing_shared.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mobile app mockup — the lender Home screen, as the app actually renders it
// ─────────────────────────────────────────────────────────────────────────────
//
// Mirrors `MobileScaffold` + the lender dashboard: navy app bar titled
// "Account" with the support and notification actions, the welcome greeting,
// the active-loan card with its outstanding balance and repayment progress,
// the recent-activity list, and the floating bottom navigation pill
// (Home / Payments / Transaction / Profile).

/// Fixed design canvas of the phone screen. The content is rendered once at
/// this size and then uniformly scaled into the device frame, so the mockup
/// keeps its exact proportions at every breakpoint.
const double _kPhoneCanvasWidth = 300;
const double _kPhoneCanvasHeight = 620;
const double _kPhoneAspect = _kPhoneCanvasWidth / _kPhoneCanvasHeight;

/// App shell page background (AppColors.cPageBg, light mode).
const Color _kPageBg = Color(0xFFF0F2F5);

/// Brand navy used by the app bar and the loan card (AppColors.lenderBlue).
const Color _kBrandNavy = Color(0xFF0D1B2A);

class JiretaPhoneMockup extends StatelessWidget {
  /// Outer width of the device. Height follows the 1:2 device ratio.
  final double width;

  const JiretaPhoneMockup({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: _kPhoneAspect,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(width * 0.16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF20334A),
                LandingPalette.navyDeep,
                Color(0xFF1A2E45),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: LandingPalette.navy.withValues(alpha: 0.28),
                blurRadius: 46,
                offset: const Offset(0, 26),
              ),
              BoxShadow(
                color: LandingPalette.gold.withValues(alpha: 0.07),
                blurRadius: 22,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: EdgeInsets.all(width * 0.03),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(width * 0.13),
            child: const ColoredBox(
              color: Colors.white,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _kPhoneCanvasWidth,
                  height: _kPhoneCanvasHeight,
                  child: _PhoneScreen(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneScreen extends StatelessWidget {
  const _PhoneScreen();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PhoneStatusBar(),
            const _PhoneAppBar(),
            Expanded(
              child: Container(
                color: _kPageBg,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 14),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _WelcomeGreeting(),
                    ),
                    SizedBox(height: 12),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _ActiveLoanCard(),
                    ),
                    SizedBox(height: 16),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _RecentActivity(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // The nav pill floats above the content, like the real shell.
        const Positioned(
          left: 12,
          right: 12,
          bottom: 8,
          child: _PhoneBottomNav(),
        ),
      ],
    );
  }
}

/// Device status bar — sits on the app bar, so it inherits the navy surface.
class _PhoneStatusBar extends StatelessWidget {
  const _PhoneStatusBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBrandNavy,
      padding: const EdgeInsets.fromLTRB(18, 9, 18, 0),
      child: Row(
        children: [
          const Text(
            '9:41',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Icon(Icons.signal_cellular_alt_rounded,
              size: 11, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 4),
          Icon(Icons.wifi_rounded,
              size: 11, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 4),
          Icon(Icons.battery_full_rounded,
              size: 12, color: Colors.white.withValues(alpha: 0.85)),
        ],
      ),
    );
  }
}

/// `MobileScaffold` app bar: role accent surface, title and the two actions the
/// lender Home screen registers (support + notifications).
class _PhoneAppBar extends StatelessWidget {
  const _PhoneAppBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      color: _kBrandNavy,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Text(
            'Account',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Icon(Icons.support_agent_rounded,
              size: 17, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 12),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.notifications_outlined,
                  size: 17, color: Colors.white.withValues(alpha: 0.92)),
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                    border: Border.all(color: _kBrandNavy, width: 1.2),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Greeting block from the real `_WelcomeBanner`.
class _WelcomeGreeting extends StatelessWidget {
  const _WelcomeGreeting();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Good morning',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7A8296),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Juan Dela Cruz',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _kBrandNavy,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E3A5F), _kBrandNavy],
            ),
          ),
          child: const Text(
            'JD',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Repayment progress card — the app's `_MyLoanCard` (navy gradient, balance,
/// progress and the Pay action).
class _ActiveLoanCard extends StatelessWidget {
  const _ActiveLoanCard();

  /// Fictional demo figures — the visitor is not signed in.
  static const double _progress = 0.75;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBrandNavy, Color(0xFF1A3658)],
        ),
        boxShadow: [
          BoxShadow(
            color: _kBrandNavy.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.45),
                  ),
                ),
                child: const Text(
                  'Active Loan',
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.goldLight,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '₱20,000.00',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.96),
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Outstanding Balance',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      Container(
                        height: 6,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      FractionallySizedBox(
                        widthFactor: _progress,
                        child: Container(
                          height: 6,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.goldLight, AppColors.gold],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '75%',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.goldLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              const _LoanMeta(label: 'Next due', value: 'Dec 20'),
              const SizedBox(width: 16),
              const _LoanMeta(label: 'Paid', value: '₱15,000'),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text(
                  'Pay',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: _kBrandNavy,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoanMeta extends StatelessWidget {
  final String label;
  final String value;

  const _LoanMeta({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 7.5,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// Recent activity list — same header/row structure as the lender Home.
class _RecentActivity extends StatelessWidget {
  const _RecentActivity();

  static const List<(IconData, String, String, String)> _rows = [
    (Icons.verified_rounded, 'Payment verified', 'GCash • Ref 2471', '₱3,000'),
    (Icons.delivery_dining_rounded, 'Collection completed', 'Rider • J. Santos', '₱2,000'),
    (Icons.check_circle_outline_rounded, 'Loan approved', 'Application #2471', '₱20,000'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              'Recent Activity',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _kBrandNavy,
              ),
            ),
            Spacer(),
            Text(
              'View all',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3B5BDB),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6E9EF)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _rows.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _kBrandNavy.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_rows[i].$1,
                            size: 12, color: _kBrandNavy),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _rows[i].$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF14213D),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _rows[i].$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 8,
                                color: Color(0xFF7A8296),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _rows[i].$4,
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF14213D),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The floating bottom navigation pill — gold-rimmed white pill with the
/// selected tab in the brand gradient (lender nav: Home / Payments /
/// Transaction / Profile).
class _PhoneBottomNav extends StatelessWidget {
  const _PhoneBottomNav();

  static const List<(IconData, IconData, String)> _items = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.payments_outlined, Icons.payments, 'Payments'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Transaction'),
    (Icons.person_outline, Icons.person, 'Profile'),
  ];

  static const int _active = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFFCFCFA)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.44),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: _kBrandNavy.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: _PhoneNavItem(
                icon: i == _active ? _items[i].$2 : _items[i].$1,
                label: _items[i].$3,
                active: i == _active,
              ),
            ),
        ],
      ),
    );
  }
}

class _PhoneNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _PhoneNavItem({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _kBrandNavy,
                  Color(0xFF1A3658),
                  AppColors.gold,
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(18),
        border: active
            ? Border.all(color: Colors.white.withValues(alpha: 0.65))
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 19,
            height: 19,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.20)
                  : _kBrandNavy.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 12,
              color: active ? Colors.white : _kBrandNavy,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 6.8,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: active ? Colors.white : _kBrandNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Web mockup — the PUBLIC landing page, as it looks in a desktop browser
// ─────────────────────────────────────────────────────────────────────────────
//
// The visitor is not signed in, so the browser frame shows the same public
// marketing page they are reading — never the authenticated workspace.

/// Design canvas of the browser window. Rendered once and scaled, so the page
/// keeps its proportions whatever space it is given.
const double _kWebCanvasWidth = 820;
const double _kWebCanvasHeight = 440;
const double _kWebAspect = _kWebCanvasWidth / _kWebCanvasHeight;

class JiretaWebMockup extends StatelessWidget {
  const JiretaWebMockup({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LandingPalette.line),
        boxShadow: [
          BoxShadow(
            color: LandingPalette.navy.withValues(alpha: 0.10),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: _kWebAspect,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: const FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: _kWebCanvasWidth,
              height: _kWebCanvasHeight,
              child: _WebWindow(),
            ),
          ),
        ),
      ),
    );
  }
}

class _WebWindow extends StatelessWidget {
  const _WebWindow();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BrowserChrome(),
        Expanded(child: _SitePage()),
      ],
    );
  }
}

class _BrowserChrome extends StatelessWidget {
  const _BrowserChrome();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      color: const Color(0xFFF1F3F7),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final color in const [
            Color(0xFFFF5F57),
            Color(0xFFFEBC2E),
            Color(0xFF28C840),
          ]) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE3E6EC)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 8, color: Color(0xFF9AA2B1)),
                  SizedBox(width: 5),
                  Text(
                    'www.jireta.com',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7488),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The public site inside the browser: site navigation, the light hero and the
/// trust bar — the same blocks the visitor is scrolling through.
class _SitePage extends StatelessWidget {
  const _SitePage();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SiteNav(),
        Expanded(child: _SiteHero()),
        _SiteTrustBar(),
      ],
    );
  }
}

class _SiteNav extends StatelessWidget {
  const _SiteNav();

  static const List<String> _links = [
    'Home',
    'Features',
    'How It Works',
    'About',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9E9EE))),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.gold.withValues(alpha: 0.9),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              AssetConstants.logoJpg,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.account_balance_rounded,
                size: 10,
                color: _kBrandNavy,
              ),
            ),
          ),
          const SizedBox(width: 7),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'JIRETA',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  color: _kBrandNavy,
                  letterSpacing: 1.4,
                  height: 1,
                ),
              ),
              Text(
                'LOANS & CREDIT CORP · 1966',
                style: TextStyle(
                  fontSize: 4.6,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: Color(0xFF7A8296),
                ),
              ),
            ],
          ),
          const Spacer(),
          for (var i = 0; i < _links.length; i++) ...[
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _links[i],
                  style: TextStyle(
                    fontSize: 6.8,
                    fontWeight:
                        i == 0 ? FontWeight.w700 : FontWeight.w600,
                    color: i == 0
                        ? _kBrandNavy
                        : const Color(0xFF555568),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  height: 1.2,
                  width: i == 0 ? 12 : 0,
                  color: AppColors.gold,
                ),
              ],
            ),
            const SizedBox(width: 12),
          ],
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _kBrandNavy, width: 1.1),
            ),
            child: const Text(
              'Sign In',
              style: TextStyle(
                fontSize: 6.8,
                fontWeight: FontWeight.w700,
                color: _kBrandNavy,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kBrandNavy,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Get Started',
              style: TextStyle(
                fontSize: 6.8,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Light hero mirroring the real landing hero (Image 2): white surface,
// dark headline, CTA card and a compact look at the product UI.
class _SiteHero extends StatelessWidget {
  const _SiteHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 470,
              child: Text(
                'Lending Management System',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.16,
                  letterSpacing: -0.5,
                  color: Color(0xFF0B1220),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const SizedBox(
              width: 400,
              child: Text(
                'Manage loan applications, approvals, payments, collections, and '
                'lending operations in one secure platform.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 7.4,
                  height: 1.6,
                  color: Color(0xFF667085),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFE6EAF2)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0D1B2A).withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: _kBrandNavy,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 7.2,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 5),
                        Icon(Icons.arrow_forward_rounded,
                            size: 9, color: Colors.white),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: const Color(0xFFE6EAF2),
                      ),
                    ),
                    child: const Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: 7.2,
                        fontWeight: FontWeight.w700,
                        color: _kBrandNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '*Register online in a few minutes — sign in any time to manage '
              'an existing account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 5.2,
                height: 1.5,
                color: Color(0xFF9AA2B1),
              ),
            ),
            const SizedBox(height: 12),
            // Compact peek at the product UI the hero advertises.
            Container(
              width: 236,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1FA97A).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 11, color: Color(0xFF1FA97A)),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Loan Approved',
                        style: TextStyle(
                          fontSize: 6.4,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7A8296),
                        ),
                      ),
                      Text(
                        '₱20,000.00',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF14213D),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Repayment',
                        style: TextStyle(
                          fontSize: 6,
                          color: Color(0xFF9AA2B1),
                        ),
                      ),
                      Text(
                        '75%',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trust bar under the hero (Secure / Fast / Organized / Reliable).
class _SiteTrustBar extends StatelessWidget {
  const _SiteTrustBar();

  static const List<(IconData, String)> _items = [
    (Icons.shield_outlined, 'Secure'),
    (Icons.bolt_outlined, 'Fast'),
    (Icons.folder_open_outlined, 'Organized'),
    (Icons.workspace_premium_outlined, 'Reliable'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE9E9EE))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_items[i].$1, size: 11, color: AppColors.goldDark),
                  const SizedBox(width: 6),
                  Text(
                    _items[i].$2,
                    style: const TextStyle(
                      fontSize: 7.4,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF14213D),
                    ),
                  ),
                ],
              ),
            ),
            if (i < _items.length - 1)
              Container(
                width: 1,
                height: 16,
                color: const Color(0xFFEDEFF3),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating product cards
// ─────────────────────────────────────────────────────────────────────────────

/// A floating LMS card in the hero composition. Width/height are fixed so the
/// hero layout can position every card deterministically (never over text).
class FloatCardSpec {
  final String id;
  final double width;
  final double height;
  final Widget Function() build;

  /// Optional custom surface — used by the green "approved" accent card.
  final Color? background;
  final Color? borderColor;

  const FloatCardSpec({
    required this.id,
    required this.width,
    required this.height,
    required this.build,
    this.background,
    this.borderColor,
  });
}

/// White floating card with a gentle idle float + hover lift.
class FloatCard extends StatefulWidget {
  final FloatCardSpec spec;
  final int floatPhase;

  const FloatCard({
    super.key,
    required this.spec,
    this.floatPhase = 0,
  });

  @override
  State<FloatCard> createState() => _FloatCardState();
}

class _FloatCardState extends State<FloatCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 3200 + widget.floatPhase * 260),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lift = _hovered ? 6.0 : 0.0;
    // Accent cards (green) also tint their own shadow.
    final tint = widget.spec.background ?? LandingPalette.navy;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedBuilder(
        animation: _float,
        builder: (context, child) {
          final wave = (_float.value - 0.5) * 2; // -1 → 1
          return Transform.translate(
            offset: Offset(0, wave * 5 - lift),
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: widget.spec.width,
          height: widget.spec.height,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: widget.spec.background ?? Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: widget.spec.borderColor ??
                  (_hovered
                      ? LandingPalette.navy.withValues(alpha: 0.14)
                      : LandingPalette.line),
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.26),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                    BoxShadow(
                      color: LandingPalette.gold.withValues(alpha: 0.10),
                      blurRadius: 14,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.16),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
          ),
          child: widget.spec.build(),
        ),
      ),
    );
  }
}

/// Compact two-line row: badge + title/subtitle. Used by most float cards.
class FloatCardRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? value;
  final bool valueFirst;

  const FloatCardRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.value,
    this.valueFirst = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: LandingPalette.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 8.5,
                  color: LandingPalette.faint,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: 8),
          Text(
            value!,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: LandingPalette.navy,
            ),
          ),
        ],
      ],
    );
  }
}

/// Repayment progress card body.
class FloatProgressBody extends StatelessWidget {
  final double progress;
  final String label;

  const FloatProgressBody({
    super.key,
    this.progress = 0.75,
    this.label = '75%',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Repayment Progress',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: LandingPalette.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: LandingPalette.navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: LandingPalette.navy.withValues(alpha: 0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(
              LandingPalette.accent,
            ),
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          '₱15,000 of ₱20,000 paid',
          style: TextStyle(
            fontSize: 8.5,
            color: LandingPalette.faint,
          ),
        ),
      ],
    );
  }
}

/// Bar chart card body.
class FloatChartBody extends StatelessWidget {
  const FloatChartBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Monthly Collections',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: LandingPalette.ink,
          ),
        ),
        SizedBox(height: 8),
        Expanded(
          child: MiniBarChart(
            values: [0.35, 0.55, 0.42, 0.70, 0.58, 0.95],
            highlightIndex: 5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tiny chart painters (no extra dependencies, cheap to paint)
// ─────────────────────────────────────────────────────────────────────────────

class MiniBarChart extends StatelessWidget {
  final List<double> values;
  final int highlightIndex;

  const MiniBarChart({
    super.key,
    required this.values,
    this.highlightIndex = -1,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarChartPainter(
        values: values,
        highlightIndex: highlightIndex,
      ),
      size: Size.infinite,
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final int highlightIndex;

  _BarChartPainter({required this.values, required this.highlightIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    const gap = 6.0;
    final barWidth = ((size.width - gap * (values.length - 1)) / values.length)
        .clamp(2.0, 22.0);
    final radius = Radius.circular(barWidth / 2);

    final basePaint = Paint()..color = LandingPalette.navy.withValues(alpha: 0.10);
    final accentPaint = Paint()..color = LandingPalette.accent;
    final highlightPaint = Paint()..color = LandingPalette.navy;

    final totalWidth = barWidth * values.length + gap * (values.length - 1);
    final startX = (size.width - totalWidth) / 2;

    for (var i = 0; i < values.length; i++) {
      final x = startX + i * (barWidth + gap);
      // Track
      final trackRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 0, barWidth, size.height),
        radius,
      );
      canvas.drawRRect(trackRect, basePaint);

      final barHeight = (size.height * values[i]).clamp(3.0, size.height);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - barHeight, barWidth, barHeight),
        radius,
      );
      canvas.drawRRect(
        rect,
        i == highlightIndex ? highlightPaint : accentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.highlightIndex != highlightIndex;
}

// ─────────────────────────────────────────────────────────────────────────────
// Decorative pieces
// ─────────────────────────────────────────────────────────────────────────────

/// Soft organic backdrop that sits behind the lower half of the device — it
/// gives the hero the same grounded, layered feel as the reference layout.
class LandingBackdropBlob extends StatelessWidget {
  const LandingBackdropBlob({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BlobPainter(),
      size: Size.infinite,
    );
  }
}

class _BlobPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0, h * 0.34)
      ..quadraticBezierTo(w * 0.13, h * 0.06, w * 0.33, h * 0.17)
      ..quadraticBezierTo(w * 0.51, h * 0.27, w * 0.68, h * 0.09)
      ..quadraticBezierTo(w * 0.87, h * -0.05, w, h * 0.22)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B3F8F), Color(0xFF1B2145), Color(0xFF0D1B2A)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

