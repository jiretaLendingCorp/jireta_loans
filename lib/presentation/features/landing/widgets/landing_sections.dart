// lib/presentation/features/landing/widgets/landing_sections.dart
//
// Marketing sections of the PUBLIC landing page. Everything here is static
// copy + illustrative UI — the page never touches authenticated providers or
// real lending records.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../shared/utils/file_downloader.dart';
import 'landing_mockups.dart';
import 'landing_shared.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 2. Trust / value bar
// ─────────────────────────────────────────────────────────────────────────────

class LandingTrustBar extends StatelessWidget {
  const LandingTrustBar({super.key});

  static const List<(IconData, String, String, Color)> _items = [
    (
      Icons.shield_outlined,
      'Secure',
      'Protected accounts and encrypted financial records.',
      LandingPalette.navy,
    ),
    (
      Icons.bolt_rounded,
      'Fast',
      'Applications reviewed and released without long queues.',
      LandingPalette.amber,
    ),
    (
      Icons.layers_outlined,
      'Organized',
      'Loans, payments and collections in one shared workspace.',
      LandingPalette.accent,
    ),
    (
      Icons.verified_outlined,
      'Reliable',
      'Accurate schedules, balances and receipts every time.',
      LandingPalette.green,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = LandingBreakpoints.isDesktop(width);
    final columns = isDesktop ? 4 : (width < 560 ? 1 : 2);

    return LandingContainer(
      child: LandingReveal(
        child: LandingCard(
          radius: 22,
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 30 : 18,
            vertical: 26,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 14.0;
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: 20,
                children: [
                  for (var i = 0; i < _items.length; i++)
                    SizedBox(
                      width: tileWidth,
                      child: _TrustItem(
                        icon: _items[i].$1,
                        title: _items[i].$2,
                        body: _items[i].$3,
                        color: _items[i].$4,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color color;

  const _TrustItem({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LandingIconBadge(icon: icon, color: color, size: 44),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: LandingPalette.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  color: LandingPalette.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Lending management features
// ─────────────────────────────────────────────────────────────────────────────

class LandingFeaturesSection extends StatelessWidget {
  const LandingFeaturesSection({super.key});

  static const List<(IconData, String, String, Color)> _features = [
    (
      Icons.request_quote_outlined,
      'Loan Applications',
      'Capture lender applications digitally with guided forms, document uploads and built-in validation.',
      LandingPalette.accent,
    ),
    (
      Icons.fact_check_outlined,
      'Loan Approval',
      'Move applications through credit investigation, review and approval with a clear, auditable trail.',
      LandingPalette.navy,
    ),
    (
      Icons.receipt_long_outlined,
      'Payment Tracking',
      'Record GCash, walk-in and field collections, then reconcile each payment against the right account.',
      LandingPalette.green,
    ),
    (
      Icons.calendar_month_outlined,
      'Repayment Schedules',
      'Generate amortisation schedules automatically and monitor every due date, balance and penalty.',
      LandingPalette.teal,
    ),
    (
      Icons.route_outlined,
      'Collections Management',
      'Assign riders to field collections, follow their visits in real time and capture proof of collection on site.',
      LandingPalette.amber,
    ),
    (
      Icons.people_alt_outlined,
      'Lender / Client Management',
      'Keep lender profiles, documents, contacts and the full account history of every client in one record.',
      LandingPalette.accent,
    ),
    (
      Icons.notifications_active_outlined,
      'Notifications',
      'Send in-app and push updates for approvals, due dates, penalties and payment confirmations.',
      LandingPalette.navy,
    ),
    (
      Icons.insights_outlined,
      'Reports & Analytics',
      'Export PDF and Excel reports on disbursements, collections, renewals and portfolio performance.',
      LandingPalette.green,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = LandingBreakpoints.isDesktop(width)
        ? 4
        : (width >= LandingBreakpoints.tablet ? 2 : 1);

    return LandingContainer(
      child: Column(
        children: [
          const LandingReveal(
            child: LandingSectionHeading(
              eyebrow: 'Lending management',
              title: 'Everything lending operations need',
              subtitle:
                  'One platform for applications, approvals, payments, collections '
                  'and reporting — built around how a real lending business works.',
            ),
          ),
          const SizedBox(height: 40),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 18.0;
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < _features.length; i++)
                    SizedBox(
                      width: tileWidth,
                      child: LandingReveal(
                        order: i % columns,
                        child: _FeatureCard(
                          icon: _features[i].$1,
                          title: _features[i].$2,
                          body: _features[i].$3,
                          color: _features[i].$4,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color color;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -5 : 0, 0),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hovered
                ? widget.color.withValues(alpha: 0.30)
                : LandingPalette.line,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: LandingPalette.navy.withValues(alpha: 0.14),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ]
              : LandingPalette.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LandingIconBadge(icon: widget.icon, color: widget.color, size: 48),
            const SizedBox(height: 18),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: LandingPalette.ink,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              widget.body,
              style: const TextStyle(
                fontSize: 12.8,
                height: 1.62,
                color: LandingPalette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. How it works
// ─────────────────────────────────────────────────────────────────────────────

class LandingHowItWorksSection extends StatelessWidget {
  const LandingHowItWorksSection({super.key});

  static const List<(String, String, String, IconData)> _steps = [
    (
      '01',
      'Apply',
      'Create your account and submit your loan application with the required details and documents.',
      Icons.edit_document,
    ),
    (
      '02',
      'Review',
      'Our team validates your information and schedules a credit investigation when it is needed.',
      Icons.search_rounded,
    ),
    (
      '03',
      'Approve',
      'Approved applications are released and your repayment schedule is generated automatically.',
      Icons.task_alt_rounded,
    ),
    (
      '04',
      'Manage & Repay',
      'Track your balance, receive due-date reminders and pay via GCash or over the counter.',
      Icons.account_balance_wallet_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = LandingBreakpoints.isDesktop(width);

    return LandingContainer(
      child: Column(
        children: [
          const LandingReveal(
            child: LandingSectionHeading(
              eyebrow: 'How it works',
              title: 'From application to full repayment',
              subtitle:
                  'A simple, transparent process for lenders — and a repeatable one '
                  'for the team behind every account.',
            ),
          ),
          const SizedBox(height: 44),
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Expanded(
                    child: LandingReveal(
                      order: i,
                      child: _StepItem(
                        index: i,
                        total: _steps.length,
                        number: _steps[i].$1,
                        title: _steps[i].$2,
                        body: _steps[i].$3,
                        icon: _steps[i].$4,
                      ),
                    ),
                  ),
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < _steps.length; i++)
                  LandingReveal(
                    order: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: _StepItemVertical(
                        index: i,
                        total: _steps.length,
                        number: _steps[i].$1,
                        title: _steps[i].$2,
                        body: _steps[i].$3,
                        icon: _steps[i].$4,
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

class _StepItem extends StatelessWidget {
  final int index;
  final int total;
  final String number;
  final String title;
  final String body;
  final IconData icon;

  const _StepItem({
    required this.index,
    required this.total,
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _Connector(visible: index > 0)),
              _StepCircle(number: number, icon: icon),
              Expanded(child: _Connector(visible: index < total - 1)),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: LandingPalette.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: LandingPalette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepItemVertical extends StatelessWidget {
  final int index;
  final int total;
  final String number;
  final String title;
  final String body;
  final IconData icon;

  const _StepItemVertical({
    required this.index,
    required this.total,
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            _StepCircle(number: number, icon: icon, size: 50),
            if (index < total - 1)
              Container(
                width: 2,
                height: 52,
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      LandingPalette.navy.withValues(alpha: 0.22),
                      LandingPalette.navy.withValues(alpha: 0.04),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: LandingPalette.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: LandingPalette.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Connector extends StatelessWidget {
  final bool visible;

  const _Connector({required this.visible});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.4,
      decoration: BoxDecoration(
        gradient: visible
            ? LinearGradient(
                colors: [
                  LandingPalette.navy.withValues(alpha: 0.06),
                  LandingPalette.navy.withValues(alpha: 0.20),
                ],
              )
            : null,
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  final String number;
  final IconData icon;
  final double size;

  const _StepCircle({
    required this.number,
    required this.icon,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: LandingPalette.navy.withValues(alpha: 0.14),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: LandingPalette.navy.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: size * 0.28, color: LandingPalette.navy),
          const SizedBox(height: 2),
          Text(
            number,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: LandingPalette.gold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Mobile + web experience
// ─────────────────────────────────────────────────────────────────────────────

class LandingDevicesSection extends StatelessWidget {
  const LandingDevicesSection({super.key});

  static const List<String> _points = [
    'Riders use the Android app for field collections, credit investigation and payments on the go.',
    'Use the web workspace on desktop for approvals, lender records and reporting.',
    'The same data, the same rules and the same security on every screen — kept in sync.',
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = LandingBreakpoints.isDesktop(width);

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LandingSectionHeading(
          eyebrow: 'Mobile + web',
          title: 'One platform. Every device.',
          subtitle:
              'Jireta runs as a responsive web workspace and as a mobile app, so '
              'lenders, riders, office staff and managers all work from the same system.',
          center: false,
          titleSize: 32,
        ),
        const SizedBox(height: 24),
        for (final point in _points)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: LandingPalette.green.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 14, color: LandingPalette.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    point,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.62,
                      color: LandingPalette.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final mockups = isDesktop
        ? const Column(
            children: [
              JiretaWebMockup(),
              SizedBox(height: 22),
              Align(
                alignment: Alignment.centerRight,
                child: JiretaPhoneMockup(width: 186),
              ),
            ],
          )
        : Column(
            children: [
              Center(child: JiretaPhoneMockup(width: width < 420 ? 190 : 220)),
              const SizedBox(height: 24),
              const JiretaWebMockup(),
            ],
          );

    return Container(
      color: const Color(0xFFF1F4FA),
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: LandingContainer(
        child: LandingReveal(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 5, child: copy),
                    const SizedBox(width: 48),
                    Expanded(flex: 6, child: mockups),
                  ],
                )
              else ...[
                copy,
                const SizedBox(height: 40),
                mockups,
              ],
              if (kIsWeb) ...[
                const SizedBox(height: 40),
                const Center(child: _LandingApkDownloadButton()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Download APK button — moved here from the web login page so visitors can
/// get the Android app straight from the landing page (web only; pointless
/// inside the native app itself, hence the [kIsWeb] gate at the call site).
class _LandingApkDownloadButton extends StatefulWidget {
  const _LandingApkDownloadButton();

  @override
  State<_LandingApkDownloadButton> createState() =>
      _LandingApkDownloadButtonState();
}

class _LandingApkDownloadButtonState extends State<_LandingApkDownloadButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await downloadFromUrl(
        AppConfig.apkDownloadUrl,
        filename: AppConfig.apkFileName,
      );
      if (ok || !mounted) return;
      context.showErrorToast(
        'The Android app is not available for download right now. '
        'Please try again later.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 0,
      runSpacing: 0,
      children: [
        MouseRegion(
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
            onTap: _download,
            child: AnimatedScale(
              scale: _pressed ? 0.975 : (_hovered ? 1.02 : 1.0),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LandingPalette.navyGradient,
                  boxShadow: (_hovered || _pressed)
                      ? [
                          BoxShadow(
                            color:
                                LandingPalette.navy.withValues(alpha: 0.30),
                            blurRadius: 26,
                            offset: const Offset(0, 14),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color:
                                LandingPalette.navy.withValues(alpha: 0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_busy)
                      const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(Icons.android_rounded,
                          size: 19, color: Colors.white),
                    const SizedBox(width: 10),
                    const Text(
                      'Download APK',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Security
// ─────────────────────────────────────────────────────────────────────────────

class LandingSecuritySection extends StatelessWidget {
  const LandingSecuritySection({super.key});

  static const List<(IconData, String, String)> _items = [
    (
      Icons.lock_person_outlined,
      'Secure authentication',
      'Every account is verified before access, and account activity is monitored for anything unusual.',
    ),
    (
      Icons.verified_user_outlined,
      'OTP verification',
      'One-time passwords confirm sensitive actions so a stolen password alone is never enough.',
    ),
    (
      Icons.enhanced_encryption_outlined,
      'Protected financial data',
      'Loan and payment records are encrypted in transit and stored behind restricted, monitored access.',
    ),
    (
      Icons.admin_panel_settings_outlined,
      'Role-based access',
      'Lenders, riders, employees and managers each only reach the screens and records their role allows.',
    ),
    (
      Icons.cloud_done_outlined,
      'Secure API architecture',
      'All app traffic travels over HTTPS through a controlled API layer with validation and audit logging.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = LandingBreakpoints.isDesktop(width)
        ? 3
        : (width >= LandingBreakpoints.tablet ? 2 : 1);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1725), Color(0xFF12263C), Color(0xFF0B1725)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GridPatternPainter(),
                size: Size.infinite,
              ),
            ),
          ),
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    LandingPalette.gold.withValues(alpha: 0.10),
                    LandingPalette.gold.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 76),
            child: LandingContainer(
              child: Column(
                children: [
                  const LandingReveal(
                    child: LandingSectionHeading(
                      eyebrow: 'Security',
                      title: 'Built to protect every account',
                      subtitle:
                          'Lending runs on trust. Jireta protects sign-in, lender '
                          'details and payment records with layered safeguards across '
                          'the app and the web workspace.',
                      onDark: true,
                    ),
                  ),
                  const SizedBox(height: 42),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 16.0;
                      final tileWidth =
                          (constraints.maxWidth - gap * (columns - 1)) / columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (var i = 0; i < _items.length; i++)
                            SizedBox(
                              width: tileWidth,
                              child: LandingReveal(
                                order: i,
                                child: _SecurityCard(
                                  icon: _items[i].$1,
                                  title: _items[i].$2,
                                  body: _items[i].$3,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  const LandingReveal(
                    order: 2,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _SecurityChip('Encrypted data in transit'),
                        _SecurityChip('Verified sign-in'),
                        _SecurityChip('Audited access'),
                        _SecurityChip('Session protection'),
                      ],
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

class _SecurityCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String body;

  const _SecurityCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  State<_SecurityCard> createState() => _SecurityCardState();
}

class _SecurityCardState extends State<_SecurityCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: _hovered ? 0.09 : 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: _hovered ? 0.22 : 0.10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: LandingPalette.gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: LandingPalette.gold.withValues(alpha: 0.26),
                ),
              ),
              child: Icon(widget.icon, size: 20, color: LandingPalette.goldSoft),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              widget.body,
              style: TextStyle(
                fontSize: 12.6,
                height: 1.62,
                color: Colors.white.withValues(alpha: 0.68),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityChip extends StatelessWidget {
  final String label;

  const _SecurityChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 13, color: LandingPalette.goldSoft),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    const gap = 46.0;
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

// ─────────────────────────────────────────────────────────────────────────────
// About
// ─────────────────────────────────────────────────────────────────────────────

class LandingAboutSection extends StatelessWidget {
  const LandingAboutSection({super.key});

  static const List<(IconData, String, String)> _values = [
    (
      Icons.handshake_outlined,
      'Responsible lending',
      'Fair terms, clear schedules and honest communication with every lender.',
    ),
    (
      Icons.support_agent_rounded,
      'Personal service',
      'A local team that knows its lenders — supported by tools, not replaced by them.',
    ),
    (
      Icons.auto_graph_rounded,
      'Modern operations',
      'Paperless records and real-time tracking for riders, office staff and managers alike.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = LandingBreakpoints.isDesktop(width);

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LandingSectionHeading(
          eyebrow: 'About',
          title: 'Serving Filipino lenders since 1966',
          subtitle:
              'Jireta Loans & Credit Corp. has built its business on long-term '
              'relationships with the families and small businesses it serves. This '
              'platform brings those decades of lending experience into one organised, '
              'digital workspace.',
          center: false,
          titleSize: 32,
        ),
        const SizedBox(height: 26),
        for (final value in _values)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LandingIconBadge(
                  icon: value.$1,
                  color: LandingPalette.gold,
                  size: 42,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.$2,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: LandingPalette.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value.$3,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.6,
                          color: LandingPalette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final companyCard = LandingCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: LandingPalette.gold.withValues(alpha: 0.4),
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: Image.asset(
                    AssetConstants.logoJpg,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: LandingPalette.navy,
                      child: Icon(Icons.account_balance_rounded,
                          size: 22, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'JIRETA',
                      style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.4,
                        height: 1.1,
                        color: LandingPalette.navy,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Loans & Credit Corp.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: LandingPalette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(height: 1, color: LandingPalette.line),
          const SizedBox(height: 20),
          const _CompanyRow(
            icon: Icons.support_agent_rounded,
            label: 'Support line',
            value: AppConstants.supportPhone,
          ),
          const SizedBox(height: 14),
          const _CompanyRow(
            icon: Icons.badge_outlined,
            label: 'Registered name',
            value: AppConstants.companyName,
          ),
          const SizedBox(height: 14),
          const _CompanyRow(
            icon: Icons.place_outlined,
            label: 'Branches',
            value: 'Walk-in applications and payments welcome',
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: LandingPalette.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: LandingPalette.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Register online to apply for a loan or to follow up an existing account.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: LandingPalette.navy.withValues(alpha: 0.82),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return LandingContainer(
      child: LandingReveal(
        child: isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: copy),
                  const SizedBox(width: 52),
                  Expanded(flex: 5, child: companyCard),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  copy,
                  const SizedBox(height: 34),
                  companyCard,
                ],
              ),
      ),
    );
  }
}

class _CompanyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CompanyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: LandingPalette.faint),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: LandingPalette.faint,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  color: LandingPalette.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Final CTA + footer
// ─────────────────────────────────────────────────────────────────────────────

class LandingFinalCta extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const LandingFinalCta({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < LandingBreakpoints.tablet;

    return LandingContainer(
      child: LandingReveal(
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 24 : 56,
            vertical: compact ? 40 : 56,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LandingPalette.navyGradient,
            boxShadow: [
              BoxShadow(
                color: LandingPalette.navy.withValues(alpha: 0.26),
                blurRadius: 40,
                offset: const Offset(0, 22),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -90,
                right: -40,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        LandingPalette.gold.withValues(alpha: 0.16),
                        LandingPalette.gold.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                  Text(
                    'Ready to simplify lending?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 25 : 36,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.9,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(
                      'Open a Jireta account to apply for a loan, or sign in to your '
                      'workspace to keep managing your account and payments.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact ? 13.5 : 15,
                        height: 1.65,
                        color: Colors.white.withValues(alpha: 0.74),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 14,
                    runSpacing: 12,
                    children: [
                      LandingPrimaryButton(
                        label: 'Get Started',
                        trailingIcon: Icons.arrow_forward_rounded,
                        onTap: onGetStarted,
                      ),
                      LandingGhostButton(
                        label: 'Sign In',
                        onTap: onSignIn,
                        onDark: true,
                      ),
                    ],
                  ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

