// lib/presentation/features/head_manager/dashboard/widgets/hm_charts_panel.dart
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';

class HmChartsPanel extends StatelessWidget {
  const HmChartsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _ChartCard(
            title: 'Loans by Status',
            child: _DonutChartPlaceholder(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _ChartCard(
            title: 'Monthly Disbursements vs Collections',
            child: _BarChartPlaceholder(),
          ),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(height: 160, child: child),
        ],
      ),
    );
  }
}

class _DonutChartPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      ('Active', AppColors.success, 0.35),
      ('Pending', AppColors.warning, 0.25),
      ('Completed', AppColors.info, 0.20),
      ('Overdue', AppColors.error, 0.10),
      ('Rejected', AppColors.textTertiary, 0.10),
    ];
    return Row(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _DonutPainter(items.map((e) => (e.$2, e.$3)).toList()),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: e.$2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    e.$1,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<(Color, double)> segments;

  _DonutPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width < size.height ? size.width : size.height) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28;
    double startAngle = -1.5708;

    for (final (color, fraction) in segments) {
      paint.color = color;
      final sweep = fraction * 2 * 3.14159;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius - 14),
        startAngle,
        sweep - 0.05,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class _BarChartPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
    const disbValues = [0.6, 0.8, 0.5, 0.9, 0.7, 0.85];
    const collValues = [0.5, 0.7, 0.45, 0.8, 0.65, 0.75];

    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(months.length, (i) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            width: 14,
                            height: disbValues[i] * 100,
                            decoration: BoxDecoration(
                              color: AppColors.deepNavy.withValues(alpha: 0.7),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3)),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Container(
                            width: 14,
                            height: collValues[i] * 100,
                            decoration: BoxDecoration(
                              color:
                                  AppColors.riderGreen.withValues(alpha: 0.7),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: months.map((m) {
                return Text(
                  m,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Legend('Disbursed', AppColors.deepNavy.withValues(alpha: 0.7)),
                const SizedBox(width: 16),
                _Legend(
                    'Collected', AppColors.riderGreen.withValues(alpha: 0.7)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final Color color;

  const _Legend(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
