// lib/presentation/features/lender/dashboard/screens/widgets/lender_promo_carousel.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_colors.dart';

/// Reusable promo data — palitan / dagdagan lang ang list na ito
/// para baguhin ang carousel nang hindi ginagalaw ang UI logic.
class LenderPromoItem {
  /// Kung may image, full-bleed banner ito (gaya ng 2 assets).
  /// Kung null, gradient + icon card ang ire-render.
  final String? imageAsset;
  final String badge;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final List<Color> gradient;
  final IconData icon;

  const LenderPromoItem({
    this.imageAsset,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.gradient,
    required this.icon,
  });
}

/// Default promos — 2 image banners mula sa assets.
const defaultLenderPromos = <LenderPromoItem>[
  LenderPromoItem(
    imageAsset: 'assets/images/PROMOTION.png',
    badge: 'Best Offer',
    title: 'Get up to ₱500,000',
    subtitle: 'Fast · Secure · Flexible',
    ctaLabel: 'Apply Loan',
    gradient: [Color(0xFF0D1B2A), Color(0xFF1A3658)],
    icon: Icons.account_balance_wallet_rounded,
  ),
  LenderPromoItem(
    imageAsset: 'assets/images/PROMOTION1.png',
    badge: 'Doorstep Service',
    title: 'Cash on Delivery',
    subtitle: 'Funds delivered by rider',
    ctaLabel: 'Cash on Delivery',
    gradient: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
    icon: Icons.delivery_dining_rounded,
  ),
];

/// Clean, modern promotional carousel.
///
/// - Auto-slides right → left gamit ang [Timer] + [PageController].
/// - Manual swipe supported (PageView).
/// - Pagination dots sa baba.
/// - Responsive for mobile & web.
/// - Reusable: magpasa lang ng ibang [banners] para baguhin ang content.
class LenderPromoCarousel extends StatefulWidget {
  final List<LenderPromoItem> banners;
  final void Function(int index, LenderPromoItem item)? onCtaTap;
  final Duration autoPlayInterval;
  final double mobileHeight;
  final double webHeight;

  const LenderPromoCarousel({
    super.key,
    this.banners = defaultLenderPromos,
    this.onCtaTap,
    this.autoPlayInterval = const Duration(seconds: 4),
    this.mobileHeight = 170,
    this.webHeight = 200,
  });

  @override
  State<LenderPromoCarousel> createState() => _LenderPromoCarouselState();
}

class _LenderPromoCarouselState extends State<LenderPromoCarousel> {
  late final PageController _controller;
  Timer? _timer;
  Timer? _resumeTimer;
  int _current = 0;
  bool _userHolding = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _timer?.cancel();
    if (widget.banners.length < 2) return;
    _timer = Timer.periodic(widget.autoPlayInterval, (_) => _goToNext());
  }

  void _pauseAutoPlay() {
    _timer?.cancel();
    _resumeTimer?.cancel();
  }

  void _scheduleResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_userHolding) _startAutoPlay();
    });
  }

  void _goToNext() {
    if (!mounted) return;
    if (!_controller.hasClients) return;
    if (_userHolding) return;
    final next = (_current + 1) % widget.banners.length;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    // Safe cleanup — hihinto ang auto-scroll pag na-dispose ang widget.
    _timer?.cancel();
    _resumeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();

    // Room reserved INSIDE the viewport for the card shadow
    // (blur 14 + offset 6) so it is never clipped and never
    // paints over the indicators / content below.
    const shadowTopRoom = 6.0;
    const shadowBottomRoom = 12.0;

    // Centered max width so the banner doesn't stretch full-bleed on web.
    // Mobile widths (< 720) are unaffected.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWeb = constraints.maxWidth > 600;
            // Fixed height matching the Outstanding Balance card so the
            // carousel and balance card share the same visual height.
            final maxCardH = isWeb ? widget.webHeight : widget.mobileHeight;
            final cardH = maxCardH;
            final height = cardH + shadowTopRoom + shadowBottomRoom;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: height,
                  child: Listener(
                    onPointerDown: (_) {
                      _userHolding = true;
                      _pauseAutoPlay();
                    },
                    onPointerUp: (_) {
                      _userHolding = false;
                      _scheduleResume();
                    },
                    onPointerCancel: (_) {
                      _userHolding = false;
                      _scheduleResume();
                    },
                    child: PageView.builder(
                      controller: _controller,
                      // Viewport must not clip card shadows at page edges.
                      clipBehavior: Clip.none,
                      itemCount: widget.banners.length,
                      onPageChanged: (i) {
                        if (!mounted) return;
                        setState(() => _current = i);
                      },
                      itemBuilder: (context, index) {
                        final item = widget.banners[index];
                        return Padding(
                          // Vertical insets give the shadow room to paint;
                          // horizontal inset keeps the small page separation.
                          padding: const EdgeInsets.fromLTRB(
                              2, shadowTopRoom, 2, shadowBottomRoom),
                          child: _PromoCard(
                            item: item,
                            isWeb: isWeb,
                            onCtaTap: () =>
                                widget.onCtaTap?.call(index, item),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Dikit na gap bago ang dots; dikit din ang susunod na
                // section (Pay with) sa dots.
                const SizedBox(height: 4),
                // Pagination dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.banners.length, (i) {
                    final active = i == _current;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.lenderBlue
                            : AppColors.borderDark.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  final LenderPromoItem item;
  final bool isWeb;
  final VoidCallback? onCtaTap;

  const _PromoCard({
    required this.item,
    required this.isWeb,
    this.onCtaTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: item.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: item.gradient.first.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: item.imageAsset != null
          ? _ImageBanner(item: item, isWeb: isWeb, onCtaTap: onCtaTap)
          : _GradientBanner(item: item, isWeb: isWeb, onCtaTap: onCtaTap),
    );
  }
}

/// Full-bleed image banner (para sa 2 nasa assets).
/// Buong image ang visible — walang badge overlay, CTA lang sa baba.
class _ImageBanner extends StatelessWidget {
  final LenderPromoItem item;
  final bool isWeb;
  final VoidCallback? onCtaTap;

  const _ImageBanner({required this.item, required this.isWeb, this.onCtaTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          item.imageAsset!,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Container(color: Colors.white),
        ),
        // Light bottom scrim para lumutang ang CTA nang hindi tinatakpan ang artwork.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.30),
                ],
                stops: const [0.0, 0.65, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 10,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _CtaButton(label: item.ctaLabel, onTap: onCtaTap),
            ],
          ),
        ),
      ],
    );
  }
}

/// Text-led gradient banner (para sa extra promos, walang sikip).
class _GradientBanner extends StatelessWidget {
  final LenderPromoItem item;
  final bool isWeb;
  final VoidCallback? onCtaTap;

  const _GradientBanner({required this.item, required this.isWeb, this.onCtaTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Soft decorative circles — fintech feel, hindi crowded.
        Positioned(
          right: -30,
          top: -30,
          child: Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          right: 30,
          bottom: -40,
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(isWeb ? 20 : 16),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        item.badge.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isWeb ? 21 : 18,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'PlayfairDisplay',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isWeb ? 13 : 12,
                        height: 1.45,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _CtaButton(label: item.ctaLabel, onTap: onCtaTap),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Center(
                  child: Container(
                    width: isWeb ? 84 : 68,
                    height: isWeb ? 84 : 68,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(item.icon,
                        color: Colors.white, size: isWeb ? 38 : 32),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CtaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _CtaButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.lenderBlue,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_rounded,
                  size: 14, color: AppColors.lenderBlue),
            ],
          ),
        ),
      ),
    );
  }
}
