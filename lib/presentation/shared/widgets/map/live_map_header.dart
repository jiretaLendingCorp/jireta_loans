// lib/presentation/shared/widgets/map/live_map_header.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Reusable "Live Map Tracking" header with animated pulsing dot.
/// Used by both Lender and Rider home cards so the UX is consistent.
class LiveMapHeader extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Color accentColor;
  final bool isLive;

  const LiveMapHeader({
    super.key,
    this.title = 'Live Map Tracking',
    this.subtitle,
    this.accentColor = AppColors.success,
    this.isLive = true,
  });

  @override
  State<LiveMapHeader> createState() => _LiveMapHeaderState();
}

class _LiveMapHeaderState extends State<LiveMapHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.map_outlined,
                        size: 16, color: widget.accentColor),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        _LiveBadge(isLive: widget.isLive, pulseCtrl: _pulseCtrl),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final bool isLive;
  final AnimationController pulseCtrl;
  const _LiveBadge({required this.isLive, required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    if (!isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pause_circle_outline,
                size: 12, color: AppColors.textTertiary),
            SizedBox(width: 5),
            Text('Paused',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: pulseCtrl,
            builder: (_, __) {
              final scale = 0.85 + 0.3 * pulseCtrl.value;
              final opacity = (1 - pulseCtrl.value).clamp(0.0, 1.0);
              return Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: opacity * 0.5,
                    child: Container(
                      width: 10 * scale,
                      height: 10 * scale,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 6),
          const Text(
            'Live',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pulsing dot used inside map overlays (e.g. "Following" chip).
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulsingDot({super.key, this.color = AppColors.success, this.size = 8});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final scale = 0.9 + 0.4 * _ctrl.value;
        final opacity = (1 - _ctrl.value).clamp(0.0, 1.0);
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: opacity * 0.45,
              child: Container(
                width: widget.size * 1.6 * scale,
                height: widget.size * 1.6 * scale,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ],
        );
      },
    );
  }
}
