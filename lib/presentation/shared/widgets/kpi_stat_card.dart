// lib/presentation/shared/widgets/kpi_stat_card.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class KpiStatCard extends StatefulWidget {
  final String title;
  final dynamic value;
  final IconData icon;
  final Color color;
  final bool isCurrency;
  final String? subtitle;
  final VoidCallback? onTap;

  const KpiStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.isCurrency = false,
    this.subtitle,
    this.onTap,
  });

  @override
  State<KpiStatCard> createState() => _KpiStatCardState();
}

class _KpiStatCardState extends State<KpiStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatValue(double v) {
    if (widget.isCurrency) {
      if (v >= 1000000) return '₱${(v / 1000000).toStringAsFixed(1)}M';
      if (v >= 1000) return '₱${(v / 1000).toStringAsFixed(1)}K';
      return '₱${v.toStringAsFixed(0)}';
    }
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    final numVal = (widget.value as num?)?.toDouble() ?? 0.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          final current = numVal * _anim.value;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icon, color: widget.color, size: 20),
                    ),
                    const Spacer(),
                    if (widget.subtitle != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.subtitle!,
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _formatValue(current),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
