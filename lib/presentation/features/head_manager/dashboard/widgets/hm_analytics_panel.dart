// lib/presentation/features/head_manager/dashboard/widgets/hm_analytics_panel.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/kpi_head_manager_model.dart';

/// Modern chart-based analytics section shown at the top of the Head Manager
/// dashboard. Renders live charts (donut, monthly bar, applications trend and
/// revenue breakdown).
class HmAnalyticsPanel extends StatelessWidget {
  final KpiHeadManagerModel kpi;
  const HmAnalyticsPanel({super.key, required this.kpi});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
          builder: (context, constraints) {
            final twoCols = constraints.maxWidth >= 900;
            final chart = SizedBox(
              height: 260,
              child: _ChartCard(
                title: 'Loan Portfolio by Status',
                subtitle: 'Distribution across all loan records',
                child: _LoanStatusDonut(kpi: kpi),
              ),
            );
            final bar = SizedBox(
              height: 260,
              child: _ChartCard(
                title: 'Monthly Disbursements vs Collections',
                subtitle: 'Last 6 months · verified transactions',
                child: _MonthlyBarChart(points: kpi.monthlySeries),
              ),
            );
            final line = SizedBox(
              height: 260,
              child: _ChartCard(
                title: 'Monthly Loan Applications',
                subtitle: 'Applications filed per month',
                child: _ApplicationsLineChart(points: kpi.monthlySeries),
              ),
            );
            final revenue = SizedBox(
              height: 260,
              child: _ChartCard(
                title: 'Revenue Composition',
                subtitle: 'Interest earned vs penalties collected',
                child: _RevenueBreakdown(kpi: kpi),
              ),
            );

            if (twoCols) {
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: chart),
                      const SizedBox(width: 16),
                      Expanded(child: bar),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: line),
                      const SizedBox(width: 16),
                      Expanded(child: revenue),
                    ],
                  ),
                ],
              );
            }
            return Column(
              children: [
                chart,
                const SizedBox(height: 16),
                bar,
                const SizedBox(height: 16),
                line,
                const SizedBox(height: 16),
                revenue,
              ],
            );
          },
        );
  }
}

// ── Shared chart card ───────────────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.gold, AppColors.goldDark],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── Donut: loan portfolio by status ─────────────────────────────────────────
class _LoanStatusDonut extends StatelessWidget {
  final KpiHeadManagerModel kpi;
  const _LoanStatusDonut({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final pending = math.max(
      0,
      kpi.totalLoanApplications -
          kpi.totalActiveLoans -
          kpi.totalCompletedLoans -
          kpi.totalOverdueLoans -
          kpi.totalRejectedLoans,
    );
    final items = [
      ('Active', AppColors.statusActive, kpi.totalActiveLoans),
      ('Completed', AppColors.statusCompleted, kpi.totalCompletedLoans),
      ('Overdue', AppColors.statusOverdue, kpi.totalOverdueLoans),
      ('Rejected', AppColors.error, kpi.totalRejectedLoans),
      ('Pending', AppColors.warning, pending),
    ];
    final total = items.fold<int>(0, (s, e) => s + e.$3);

    if (total == 0) {
      return const Center(
        child: Text(
          'No loan data yet',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => CustomPaint(
              painter: _DonutPainter(
                items.map((e) => (e.$2, e.$3 / total * t)).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.map((e) {
              final fraction = e.$3 / total;
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
                    Expanded(
                      child: Text(
                        e.$1,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${(fraction * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: e.$2,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
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
    final radius =
        (size.width < size.height ? size.width : size.height) / 2 - 14;
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26
      ..color = AppColors.surfaceVariant;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      0,
      2 * 3.14159,
      false,
      bgPaint,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26
      ..strokeCap = StrokeCap.butt;
    double startAngle = -1.5708;

    for (final (color, fraction) in segments) {
      if (fraction <= 0) continue;
      paint.color = color;
      final sweep = fraction * 2 * 3.14159;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        startAngle,
        sweep - 0.04,
        false,
        paint,
      );
      startAngle += sweep;
    }

    final total = segments.fold<double>(0, (s, e) => s + e.$2);
    final totalLabel = TextPainter(
      text: TextSpan(
        text: total == 0
            ? 'Total'
            : '${(total * 100).toStringAsFixed(0)}%',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: total == 0 ? AppColors.textTertiary : AppColors.deepNavy,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    totalLabel.paint(
      canvas,
      Offset(cx - totalLabel.width / 2, cy - totalLabel.height / 2 - 8),
    );

    const totalCaption = TextSpan(
      text: 'of loans',
      style: TextStyle(
        fontSize: 10,
        color: AppColors.textTertiary,
      ),
    );
    final captionPainter = TextPainter(
      text: totalCaption,
      textDirection: TextDirection.ltr,
    )..layout();
    captionPainter.paint(
      canvas,
      Offset(cx - captionPainter.width / 2, cy - captionPainter.height / 2 + 10),
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.segments != segments;
}

// ── Monthly bar: disbursements vs collections ───────────────────────────────
class _MonthlyBarChart extends StatelessWidget {
  final List<MonthlyKpiPoint> points;
  const _MonthlyBarChart({required this.points});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  String _label(String month) {
    if (month.length < 8) return month;
    final m = int.tryParse(month.substring(5, 7)) ?? 1;
    return _months[m - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(
        child: Text(
          'No trend data yet',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }

    final maxValue = points.fold<double>(
      0,
      (s, p) => math.max(s, math.max(p.released, p.collected)),
    );

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(points.length, (i) {
                  final p = points[i];
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, barConstraints) {
                                final chartHeight = barConstraints.maxHeight;
                                return Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      _AnimatedBar(
                                        heightFactor: maxValue == 0
                                            ? 0
                                            : p.released / maxValue,
                                        chartHeight: chartHeight,
                                        color: AppColors.deepNavy,
                                        tooltip:
                                            'Released: ${p.released.toCurrency}',
                                      ),
                                      const SizedBox(width: 3),
                                      _AnimatedBar(
                                        heightFactor: maxValue == 0
                                            ? 0
                                            : p.collected / maxValue,
                                        chartHeight: chartHeight,
                                        color: AppColors.riderGreen,
                                        tooltip:
                                            'Collected: ${p.collected.toCurrency}',
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _label(p.month),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend('Disbursed', AppColors.deepNavy),
            SizedBox(width: 16),
            _Legend('Collected', AppColors.riderGreen),
          ],
        ),
      ],
    );
  }
}

class _AnimatedBar extends StatelessWidget {
  final double heightFactor;
  final double chartHeight;
  final Color color;
  final String tooltip;

  const _AnimatedBar({
    required this.heightFactor,
    required this.chartHeight,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: heightFactor),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => Container(
          width: 12,
          height: t * chartHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.65)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      ),
    );
  }
}

// ── Monthly applications trend ──────────────────────────────────────────────
class _ApplicationsLineChart extends StatelessWidget {
  final List<MonthlyKpiPoint> points;
  const _ApplicationsLineChart({required this.points});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  String _label(String month) {
    if (month.length < 8) return month;
    final m = int.tryParse(month.substring(5, 7)) ?? 1;
    return _months[m - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(
        child: Text(
          'No trend data yet',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }

    final maxCount = points.fold<int>(0, (s, p) => math.max(s, p.applications));

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final stepX = w / (points.length - 1);
              final maxH = math.max(maxCount, 1);
              Offset pointAt(int i) => Offset(
                    stepX * i,
                    h - (points[i].applications / maxH) * (h - 20) - 10,
                  );

              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) {
                  Offset interp(int i) {
                    final from = pointAt(i - 1 < 0 ? 0 : i - 1);
                    final to = pointAt(i);
                    return Offset(
                      from.dx + (to.dx - from.dx) * t,
                      from.dy + (to.dy - from.dy) * t,
                    );
                  }

                  Offset easedPoint(int i) {
                    if (i == 0) return pointAt(0);
                    return interp(i);
                  }

                  final path = Path();
                  for (var i = 0; i < points.length; i++) {
                    final pt = easedPoint(i);
                    if (i == 0) {
                      path.moveTo(pt.dx, pt.dy);
                    } else {
                      path.lineTo(pt.dx, pt.dy);
                    }
                  }
                  final fill = Path.from(path)
                    ..lineTo(w, h)
                    ..lineTo(0, h)
                    ..close();

                  return Stack(
                    children: [
                      CustomPaint(
                        size: Size(w, h),
                        painter: _LineAreaPainter(path: path, fill: fill),
                      ),
                      for (var i = 0; i < points.length; i++)
                        Positioned(
                          left: stepX * i - 12,
                          top: easedPoint(i).dy - 16,
                          width: 24,
                          child: Text(
                            '${points[i].applications}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.lenderBlue,
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Row(
                          children: points
                              .map((p) => Expanded(
                                    child: Text(
                                      _label(p.month),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend('Applications', AppColors.lenderBlue),
          ],
        ),
      ],
    );
  }
}

class _LineAreaPainter extends CustomPainter {
  final Path path;
  final Path fill;
  _LineAreaPainter({required this.path, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          colors: [AppColors.lenderBlueLight, Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.lenderBlue
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LineAreaPainter old) =>
      old.path != path || old.fill != fill;
}

// ── Revenue composition ─────────────────────────────────────────────────────
class _RevenueBreakdown extends StatelessWidget {
  final KpiHeadManagerModel kpi;
  const _RevenueBreakdown({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final total = kpi.totalRevenue;
    if (total <= 0) {
      return const Center(
        child: Text(
          'No revenue data yet',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }
    final interestFrac = kpi.totalInterestEarned / total;
    final penaltyFrac = kpi.totalPenaltiesCollected / total;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 24,
            width: double.infinity,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => Row(
                children: [
                  Expanded(
                    flex: (interestFrac * t * 1000).round().clamp(1, 1000),
                    child: Container(color: AppColors.gold),
                  ),
                  Expanded(
                    flex: (penaltyFrac * t * 1000).round().clamp(1, 1000),
                    child: Container(color: AppColors.error),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _RevenueRow(
          label: 'Interest Earned',
          value: kpi.totalInterestEarned.toCurrency,
          color: AppColors.gold,
        ),
        const SizedBox(height: 8),
        _RevenueRow(
          label: 'Penalties Collected',
          value: kpi.totalPenaltiesCollected.toCurrency,
          color: AppColors.error,
        ),
        const Divider(height: 24, color: AppColors.divider),
        _RevenueRow(
          label: 'Total Revenue',
          value: total.toCurrency,
          color: AppColors.textPrimary,
          bold: true,
        ),
      ],
    );
  }
}

class _RevenueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;
  const _RevenueRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: bold ? AppColors.textPrimary : color,
            ),
          ),
        ),
      ],
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
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}