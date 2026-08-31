// lib/presentation/features/head_manager/dashboard/widgets/hm_analytics_panel.dart
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/kpi_head_manager_model.dart';

/// Analytics section shown at the top of the Head Manager dashboard.
/// Currently shows only the loan portfolio donut — other charts removed per spec.
class HmAnalyticsPanel extends StatelessWidget {
  final KpiHeadManagerModel kpi;
  const HmAnalyticsPanel({super.key, required this.kpi});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: _ChartCard(
        title: 'Loan Portfolio by Status',
        subtitle: 'Distribution across all loan records',
        icon: Icons.pie_chart_rounded,
        child: _LoanStatusDonut(kpi: kpi),
      ),
    );
  }
}

// ── Shared chart card ───────────────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final IconData icon;
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.icon,
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
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.gold, AppColors.goldDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: Colors.white),
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
class _DonutSegment {
  final String label;
  final String statusKey;
  final Color color;
  final int count;
  final IconData icon;
  const _DonutSegment(
      this.label, this.statusKey, this.color, this.count, this.icon);
}

class _LoanStatusDonut extends StatefulWidget {
  final KpiHeadManagerModel kpi;
  const _LoanStatusDonut({required this.kpi});

  @override
  State<_LoanStatusDonut> createState() => _LoanStatusDonutState();
}

class _LoanStatusDonutState extends State<_LoanStatusDonut> {
  int _hovered = -1;

  List<_DonutSegment> _segments(KpiHeadManagerModel kpi) {
    // Prefer backend breakdown when available for exact "pending" bucket;
    // fallback to derived count for backwards-compatibility.
    final int pending;
    if (kpi.loanStatusBreakdown.isNotEmpty && kpi.pendingBucket > 0) {
      pending = kpi.pendingBucket;
    } else {
      pending = math.max(
        0,
        kpi.totalLoanApplications -
            kpi.totalActiveLoans -
            kpi.totalCompletedLoans -
            kpi.totalOverdueLoans -
            kpi.totalRejectedLoans,
      );
    }
    return [
      _DonutSegment('Active', 'active', AppColors.statusActive,
          kpi.totalActiveLoans, Icons.trending_up_rounded),
      _DonutSegment('Completed', 'completed', AppColors.statusCompleted,
          kpi.totalCompletedLoans, Icons.check_circle_rounded),
      _DonutSegment('Overdue', 'overdue', AppColors.statusOverdue,
          kpi.totalOverdueLoans, Icons.warning_rounded),
      _DonutSegment('Rejected', 'rejected', AppColors.error,
          kpi.totalRejectedLoans, Icons.cancel_rounded),
      _DonutSegment('Pending', 'pending_bucket', AppColors.warning, pending,
          Icons.pending_rounded),
    ];
  }

  void _openDrill(int index) {
    final segs = _segments(widget.kpi);
    if (index < 0 || index >= segs.length) return;
    final total = segs.fold<int>(0, (s, e) => s + e.count);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PortfolioDrillSheet(
        kpi: widget.kpi,
        segments: segs,
        total: total,
        initialIndex: index,
        onNavigate: (statusKey) {
          Navigator.pop(ctx);
          // Navigate to loan records; filter hint passed via extra is best-effort
          // (route itself doesn't require it — sheet still shows correct detail).
          try {
            GoRouter.of(context).go(RouteConstants.hmLoanApplications);
          } catch (_) {}
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final segs = _segments(widget.kpi);
    final total = segs.fold<int>(0, (s, e) => s + e.count);

    if (total == 0) {
      return const Center(
        child: Text(
          'No loan data yet',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        final compactLegend =
            constraints.maxWidth < 400 || constraints.maxHeight < 220;
        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Donut chart with fl_chart — fully interactive
                      Expanded(
                        flex: isNarrow ? 5 : 4,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: compactLegend ? 28 : 34,
                            startDegreeOffset: -90,
                            pieTouchData: PieTouchData(
                              touchCallback:
                                  (FlTouchEvent event, PieTouchResponse? resp) {
                                final idx =
                                    resp?.touchedSection?.touchedSectionIndex ??
                                        -1;
                                if (event is FlTapUpEvent && idx >= 0) {
                                  _openDrill(idx);
                                  return;
                                }
                                if (event is FlLongPressEnd ||
                                    event is FlPanEndEvent) {
                                  setState(() => _hovered = -1);
                                  return;
                                }
                                if (_hovered != idx) {
                                  setState(() => _hovered = idx);
                                }
                              },
                            ),
                            sections: List.generate(segs.length, (i) {
                              final s = segs[i];
                              final isHovered = _hovered == i;
                              final pct =
                                  total == 0 ? 0 : s.count / total * 100;
                              return PieChartSectionData(
                                color: s.color,
                                value: s.count
                                    .toDouble()
                                    .clamp(0.5, double.infinity),
                                title:
                                    pct < 6 ? '' : '${pct.toStringAsFixed(0)}%',
                                titleStyle: TextStyle(
                                  fontSize: isHovered ? 12 : 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.28),
                                        blurRadius: 4),
                                  ],
                                ),
                                radius: isHovered
                                    ? (compactLegend ? 32 : 38)
                                    : (compactLegend ? 26 : 30),
                                borderSide: isHovered
                                    ? const BorderSide(
                                        color: Colors.white, width: 1.5)
                                    : BorderSide.none,
                                badgeWidget: null,
                              );
                            }),
                          ),
                          // ignore: deprecated_member_use
                          swapAnimationDuration:
                              const Duration(milliseconds: 420),
                          // ignore: deprecated_member_use
                          swapAnimationCurve: Curves.easeOutCubic,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: isNarrow ? 5 : 4,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: List.generate(segs.length, (i) {
                              final s = segs[i];
                              final isHovered = _hovered == i;
                              final pct =
                                  total == 0 ? 0 : s.count / total * 100;
                              return MouseRegion(
                                onEnter: (_) => setState(() => _hovered = i),
                                onExit: (_) => setState(() => _hovered = -1),
                                child: GestureDetector(
                                  onTap: () => _openDrill(i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    margin: EdgeInsets.symmetric(
                                        vertical: compactLegend ? 1.5 : 2.5),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: compactLegend ? 4 : 5),
                                    decoration: BoxDecoration(
                                      color: isHovered
                                          ? s.color.withValues(alpha: 0.10)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(7),
                                      border: Border.all(
                                        color: isHovered
                                            ? s.color.withValues(alpha: 0.32)
                                            : AppColors.border
                                                .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: compactLegend ? 20 : 22,
                                          height: compactLegend ? 20 : 22,
                                          decoration: BoxDecoration(
                                            color: s.color,
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            boxShadow: isHovered
                                                ? [
                                                    BoxShadow(
                                                        color: s.color
                                                            .withValues(
                                                                alpha: 0.24),
                                                        blurRadius: 6,
                                                        offset:
                                                            const Offset(0, 2))
                                                  ]
                                                : null,
                                          ),
                                          child: Icon(s.icon,
                                              size: compactLegend ? 10 : 11,
                                              color: Colors.white),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                s.label,
                                                style: TextStyle(
                                                  fontSize:
                                                      compactLegend ? 10.5 : 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: isHovered
                                                      ? s.color
                                                      : AppColors.textPrimary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                '${s.count} · ${pct.toStringAsFixed(0)}%',
                                                style: const TextStyle(
                                                    fontSize: 9.5,
                                                    color:
                                                        AppColors.textTertiary),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.chevron_right_rounded,
                                            size: 12,
                                            color: isHovered
                                                ? s.color
                                                : AppColors.textTertiary),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              ],
            ),
            // Overlay tooltip — does not affect layout so legend never overflows
            if (_hovered >= 0 && _hovered < segs.length)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _DonutTooltip(
                  key: ValueKey(_hovered),
                  segment: segs[_hovered],
                  total: total,
                  kpi: widget.kpi,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DonutTooltip extends StatelessWidget {
  final _DonutSegment segment;
  final int total;
  final KpiHeadManagerModel kpi;
  const _DonutTooltip(
      {super.key,
      required this.segment,
      required this.total,
      required this.kpi});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : segment.count / total * 100;
    final remaining = total - segment.count;
    String desc;
    switch (segment.statusKey) {
      case 'active':
        desc = 'Currently repaying · generates interest';
        break;
      case 'completed':
        desc = 'Fully repaid · closed successfully';
        break;
      case 'overdue':
        desc = 'Past due · requires collection focus';
        break;
      case 'rejected':
        desc = 'Declined applications · policy / risk';
        break;
      default:
        desc = 'In pipeline · pending review / CI / approval';
    }
    // Estimate share of released amount per status proportionally when possible
    final avgPrincipal = kpi.totalLoanApplications == 0
        ? 0
        : kpi.totalLoanAmountReleased /
            kpi.totalLoanApplications.clamp(1, 1 << 31);
    final estAmount = segment.count * avgPrincipal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.deepNavy,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
        border: Border.all(color: segment.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: segment.color, borderRadius: BorderRadius.circular(8)),
            child: Icon(segment.icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      segment.label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: segment.color,
                          borderRadius: BorderRadius.circular(99)),
                      child: Text(
                        '${pct.toStringAsFixed(1)}% of portfolio',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${segment.count} loans · $remaining others · est. ${estAmount.toCurrency} principal',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white.withValues(alpha: 0.82)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  desc,
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.62),
                      fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.open_in_new_rounded,
                    size: 11, color: Colors.white70),
                SizedBox(width: 4),
                Text('View',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioDrillSheet extends StatelessWidget {
  final KpiHeadManagerModel kpi;
  final List<_DonutSegment> segments;
  final int total;
  final int initialIndex;
  final void Function(String statusKey) onNavigate;
  const _PortfolioDrillSheet({
    required this.kpi,
    required this.segments,
    required this.total,
    required this.initialIndex,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final selected = segments[initialIndex];
    final pct = total == 0 ? 0.0 : selected.count / total * 100;
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: selected.color,
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(selected.icon, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${selected.label} Loans — Drill Down',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary),
                          ),
                          Text(
                            '${selected.count} of $total loans · ${pct.toStringAsFixed(1)}% of portfolio',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded,
                          size: 20, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const Divider(height: 20, color: AppColors.divider),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  children: [
                    // Summary cards
                    Row(
                      children: [
                        Expanded(
                          child: _DrillStatCard(
                            label: 'Selected Bucket',
                            value: '${selected.count}',
                            sub: '${pct.toStringAsFixed(1)}% share',
                            icon: selected.icon,
                            color: selected.color,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DrillStatCard(
                            label: 'Total Portfolio',
                            value: '$total',
                            sub: '${kpi.totalLoanApplications} applications',
                            icon: Icons.pie_chart_rounded,
                            color: AppColors.deepNavy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DrillStatCard(
                            label: 'Est. Principal (bucket)',
                            value: (selected.count *
                                    (kpi.totalLoanApplications == 0
                                        ? 0
                                        : kpi.totalLoanAmountReleased /
                                            kpi.totalLoanApplications
                                                .clamp(1, 1 << 31)))
                                .toCurrency,
                            sub: 'Pro-rata of released',
                            icon: Icons.payments_rounded,
                            color: AppColors.gold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DrillStatCard(
                            label: 'Avg per Loan',
                            value: (kpi.totalLoanApplications == 0
                                    ? 0
                                    : kpi.totalLoanAmountReleased /
                                        kpi.totalLoanApplications)
                                .toCurrency,
                            sub: 'Portfolio average',
                            icon: Icons.calculate_rounded,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Breakdown by Status',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    ...segments.map((s) {
                      final p = total == 0 ? 0.0 : s.count / total * 100;
                      final isSelected = s.label == selected.label;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? s.color.withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isSelected
                                  ? s.color.withValues(alpha: 0.28)
                                  : AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: s.color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(s.label,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? s.color
                                          : AppColors.textPrimary)),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${s.count} loans',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? s.color
                                            : AppColors.textPrimary)),
                                Text('${p.toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textTertiary)),
                              ],
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: (p / 100).clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: AppColors.surfaceVariant,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(s.color),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    // Backend breakdown expander
                    if (kpi.loanStatusBreakdown.isNotEmpty) ...[
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Detailed status keys (backend)',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                        subtitle: const Text(
                            'Tap to view raw counts per status key from server',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textTertiary)),
                        children: kpi.loanStatusBreakdown.entries.map((e) {
                          return ListTile(
                            dense: true,
                            title: Text(e.key,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                            trailing: Text('${e.value}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.deepNavy)),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => onNavigate(selected.statusKey),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Open Loan Records'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.deepNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),

                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DrillStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;
  const _DrillStatCard(
      {required this.label,
      required this.value,
      required this.sub,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7)),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(sub,
              style:
                  const TextStyle(fontSize: 10, color: AppColors.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Monthly bar: disbursements vs collections ───────────────────────────────
class _MonthlyBarChart extends StatefulWidget {
  final KpiHeadManagerModel kpi;
  const _MonthlyBarChart({required this.kpi});

  @override
  State<_MonthlyBarChart> createState() => _MonthlyBarChartState();
}

class _MonthlyBarChartState extends State<_MonthlyBarChart> {
  int _hovered = -1;

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

  String _fullLabel(String month) {
    if (month.length < 8) return month;
    final y = month.substring(0, 4);
    final m = int.tryParse(month.substring(5, 7)) ?? 1;
    return '${_months[m - 1]} $y';
  }

  List<MonthlyKpiPoint> get points => widget.kpi.monthlySeries;

  void _openMonthDrill(int idx) {
    if (idx < 0 || idx >= points.length) return;
    final p = points[idx];
    final prev = idx > 0 ? points[idx - 1] : null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MonthBarDrillSheet(
          point: p, prev: prev, fullLabel: _fullLabel(p.month)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(
        child: Text('No trend data yet',
            style: TextStyle(color: AppColors.textTertiary)),
      );
    }

    final maxValue = points.fold<double>(
        0, (s, p) => math.max(s, math.max(p.released, p.collected)));
    final yMax = maxValue == 0 ? 10000.0 : maxValue * 1.18;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: _hovered >= 0 ? 52 : 28),
                child: BarChart(
                  BarChartData(
                    maxY: yMax,
                    barTouchData: BarTouchData(
                      enabled: true,
                      handleBuiltInTouches: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => Colors.transparent,
                        tooltipPadding: EdgeInsets.zero,
                        tooltipMargin: 0,
                        getTooltipItem: (a, b, c, d) => null,
                      ),
                      touchCallback: (FlTouchEvent e, BarTouchResponse? resp) {
                        final idx = resp?.spot?.touchedBarGroupIndex ?? -1;
                        if (e is FlTapUpEvent && idx >= 0) {
                          _openMonthDrill(idx);
                          return;
                        }
                        if (_hovered != idx) setState(() => _hovered = idx);
                      },
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: yMax / 4,
                      getDrawingHorizontalLine: (v) => const FlLine(
                          color: AppColors.divider, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          interval: yMax / 4,
                          getTitlesWidget: (v, meta) {
                            if (v == 0) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                v >= 1000000
                                    ? '₱${(v / 1000000).toStringAsFixed(1)}M'
                                    : v >= 1000
                                        ? '₱${(v / 1000).toStringAsFixed(0)}K'
                                        : '₱${v.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 9, color: AppColors.textTertiary),
                                textAlign: TextAlign.right,
                              ),
                            );
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= points.length) {
                              return const SizedBox.shrink();
                            }
                            final isHovered = _hovered == i;
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isHovered
                                      ? AppColors.deepNavy
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _label(points[i].month),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isHovered
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: isHovered
                                          ? Colors.white
                                          : AppColors.textTertiary),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: List.generate(points.length, (i) {
                      final p = points[i];
                      final isHovered = _hovered == i;
                      return BarChartGroupData(
                        x: i,
                        barsSpace: 4,
                        barRods: [
                          BarChartRodData(
                            toY: p.released,
                            width: isHovered ? 14 : 11,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                            color: isHovered
                                ? AppColors.deepNavy
                                : AppColors.deepNavy.withValues(alpha: 0.88),
                            backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: yMax,
                                color: AppColors.surfaceVariant),
                          ),
                          BarChartRodData(
                            toY: p.collected,
                            width: isHovered ? 14 : 11,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                            color: isHovered
                                ? AppColors.riderGreen
                                : AppColors.riderGreen.withValues(alpha: 0.88),
                            backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: yMax,
                                color: AppColors.surfaceVariant),
                          ),
                        ],
                      );
                    }),
                  ),
                  // ignore: deprecated_member_use
                  swapAnimationDuration: const Duration(milliseconds: 380),
                  // ignore: deprecated_member_use
                  swapAnimationCurve: Curves.easeOutCubic,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _LegendInteractive('Disbursed', AppColors.deepNavy,
                    isHovered: _hovered >= 0),
                _LegendInteractive('Collected', AppColors.riderGreen,
                    isHovered: _hovered >= 0),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.deepNavy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    '${points.length} months',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.deepNavy.withValues(alpha: 0.7)),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (_hovered >= 0 && _hovered < points.length)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _BarTooltipCard(
              point: points[_hovered],
              prev: _hovered > 0 ? points[_hovered - 1] : null,
              fullLabel: _fullLabel(points[_hovered].month),
            ),
          ),
      ],
    );
  }
}

class _BarTooltipCard extends StatelessWidget {
  final MonthlyKpiPoint point;
  final MonthlyKpiPoint? prev;
  final String fullLabel;
  const _BarTooltipCard(
      {required this.point,
      required this.prev,
      required this.fullLabel});

  @override
  Widget build(BuildContext context) {
    final rate =
        point.released == 0 ? 0.0 : point.collected / point.released * 100;
    final deltaReleased = prev == null ? null : point.released - prev!.released;
    final deltaCollected =
        prev == null ? null : point.collected - prev!.collected;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.deepNavy,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.calendar_month_rounded,
                size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(fullLabel,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(99)),
                      child: Text('${rate.toStringAsFixed(0)}% collected',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                    if (point.applications > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99)),
                        child: Text('${point.applications} apps',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, c) {
                    final netText =
                        'Net ${(point.released - point.collected).toCurrency}';
                    return Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _MiniMoney(
                            label: 'Released',
                            value: point.released.toCurrency,
                            color: Colors.white,
                            delta: deltaReleased),
                        _MiniMoney(
                            label: 'Collected',
                            value: point.collected.toCurrency,
                            color: AppColors.riderGreenLight,
                            delta: deltaCollected),
                        Text(
                          netText,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.78)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMoney extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final double? delta;
  const _MiniMoney(
      {required this.label,
      required this.value,
      required this.color,
      this.delta});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.62),
                letterSpacing: 0.3)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: color)),
            if (delta != null) ...[
              const SizedBox(width: 4),
              Icon(
                  delta! >= 0
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 10,
                  color: delta! >= 0
                      ? AppColors.riderGreenLight
                      : AppColors.errorLight),
              Text(
                delta!.abs().toCurrency,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: delta! >= 0
                        ? AppColors.riderGreenLight
                        : AppColors.errorLight),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _MonthBarDrillSheet extends StatelessWidget {
  final MonthlyKpiPoint point;
  final MonthlyKpiPoint? prev;
  final String fullLabel;
  const _MonthBarDrillSheet(
      {required this.point, required this.prev, required this.fullLabel});

  @override
  Widget build(BuildContext context) {
    final rate =
        point.released == 0 ? 0.0 : point.collected / point.released * 100;
    final net = point.released - point.collected;
    final deltaApps =
        prev == null ? null : point.applications - prev!.applications;
    return DraggableScrollableSheet(
      initialChildSize: 0.58,
      minChildSize: 0.42,
      maxChildSize: 0.90,
      expand: false,
      builder: (ctx, ctrl) {
        return Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            children: [
              Center(
                  child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.deepNavy, AppColors.navyLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.calendar_month_rounded,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fullLabel,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        Text(
                          '${point.applications} applications · ${rate.toStringAsFixed(1)}% collection rate',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textTertiary)),
                ],
              ),
              const Divider(height: 20, color: AppColors.divider),
              Row(
                children: [
                  Expanded(
                    child: _DrillStatCard(
                      label: 'Disbursed',
                      value: point.released.toCurrency,
                      sub: prev == null
                          ? 'This month'
                          : '${(point.released - prev!.released).toCurrency} vs prev',
                      icon: Icons.outbox_rounded,
                      color: AppColors.deepNavy,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DrillStatCard(
                      label: 'Collected',
                      value: point.collected.toCurrency,
                      sub: prev == null
                          ? 'Verified'
                          : '${(point.collected - prev!.collected).toCurrency} vs prev',
                      icon: Icons.savings_rounded,
                      color: AppColors.riderGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _DrillStatCard(
                      label: 'Net Outflow',
                      value: net.toCurrency,
                      sub: net > 0 ? 'More disbursed' : 'Collections ahead',
                      icon: Icons.compare_arrows_rounded,
                      color: net > 0 ? AppColors.warning : AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DrillStatCard(
                      label: 'Applications',
                      value: '${point.applications}',
                      sub: deltaApps == null
                          ? 'Filed this month'
                          : '${deltaApps >= 0 ? '+' : ''}$deltaApps vs prev',
                      icon: Icons.description_rounded,
                      color: AppColors.lenderBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.deepNavy.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.insights_rounded,
                            size: 14, color: AppColors.deepNavy),
                        SizedBox(width: 6),
                        Text('What this means',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      rate >= 95
                          ? 'Excellent collection — nearly all disbursed funds recovered this month.'
                          : rate >= 75
                              ? 'Healthy flow — most disbursed funds are being collected on schedule.'
                              : rate >= 45
                                  ? 'Watch closely — collections lag disbursements this month.'
                                  : 'Action needed — collections are far below disbursements for $fullLabel.',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                        value: (rate / 100).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(rate >= 75
                            ? AppColors.riderGreen
                            : rate >= 45
                                ? AppColors.warning
                                : AppColors.error)),
                    const SizedBox(height: 4),
                    Text(
                        '${rate.toStringAsFixed(1)}% of disbursed amount collected',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    try {
                      GoRouter.of(context).go(RouteConstants.hmReports);
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.assessment_rounded, size: 16),
                  label: const Text('Open Reports'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Monthly applications trend ──────────────────────────────────────────────
class _ApplicationsLineChart extends StatefulWidget {
  final KpiHeadManagerModel kpi;
  const _ApplicationsLineChart({required this.kpi});

  @override
  State<_ApplicationsLineChart> createState() => _ApplicationsLineChartState();
}

class _ApplicationsLineChartState extends State<_ApplicationsLineChart> {
  int _hovered = -1;

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

  String _fullLabel(String month) {
    if (month.length < 8) return month;
    final y = month.substring(0, 4);
    final m = int.tryParse(month.substring(5, 7)) ?? 1;
    return '${_months[m - 1]} $y';
  }

  List<MonthlyKpiPoint> get points => widget.kpi.monthlySeries;

  void _openDrill(int idx) {
    if (idx < 0 || idx >= points.length) return;
    final p = points[idx];
    final prev = idx > 0 ? points[idx - 1] : null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MonthLineDrillSheet(
          point: p, prev: prev, fullLabel: _fullLabel(p.month)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(
          child: Text('No trend data yet',
              style: TextStyle(color: AppColors.textTertiary)));
    }

    final maxCount = points.fold<int>(0, (s, p) => math.max(s, p.applications));
    final yMax = math.max(maxCount, 4).toDouble() * 1.32;
    final spots = List.generate(points.length,
        (i) => FlSpot(i.toDouble(), points[i].applications.toDouble()));
    final double avg = points.isEmpty
        ? 0.0
        : points.fold<int>(0, (s, p) => s + p.applications) / points.length;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: _hovered >= 0 ? 54 : 28),
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: (points.length - 1).toDouble(),
                    minY: 0,
                    maxY: yMax,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval:
                          math.max(1, (yMax / 4).ceilToDouble()),
                      getDrawingHorizontalLine: (v) => const FlLine(
                          color: AppColors.divider, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          interval: math.max(1, (yMax / 4).ceilToDouble()),
                          getTitlesWidget: (v, meta) => Text(
                              v.toInt().toString(),
                              style: const TextStyle(
                                  fontSize: 9, color: AppColors.textTertiary)),
                        ),
                      ),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: 1,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= points.length) {
                              return const SizedBox.shrink();
                            }
                            final isHovered = _hovered == i;
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                    color: isHovered
                                        ? AppColors.lenderBlue
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(_label(points[i].month),
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: isHovered
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: isHovered
                                            ? Colors.white
                                            : AppColors.textTertiary)),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      enabled: true,
                      handleBuiltInTouches: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => Colors.transparent,
                        tooltipPadding: EdgeInsets.zero,
                        getTooltipItems: (spots) =>
                            spots.map((_) => null).toList(),
                      ),
                      touchCallback: (FlTouchEvent e, LineTouchResponse? resp) {
                        final idx =
                            resp?.lineBarSpots?.firstOrNull?.x.toInt() ?? -1;
                        if (e is FlTapUpEvent && idx >= 0) {
                          _openDrill(idx);
                          return;
                        }
                        if (_hovered != idx) setState(() => _hovered = idx);
                      },
                    ),
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: avg,
                          color: AppColors.warning.withValues(alpha: 0.22),
                          strokeWidth: 1.2,
                          dashArray: [6, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            labelResolver: (_) =>
                                'avg ${avg.toStringAsFixed(1)}',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color:
                                    AppColors.warning.withValues(alpha: 0.9)),
                          ),
                        ),
                      ],
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.22,
                        color: AppColors.lenderBlue,
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, idx) {
                            final isHovered = _hovered == idx;
                            return FlDotCirclePainter(
                              radius: isHovered ? 7 : 4.5,
                              color: isHovered
                                  ? AppColors.lenderBlue
                                  : Colors.white,
                              strokeWidth: isHovered ? 3 : 2,
                              strokeColor: AppColors.lenderBlue,
                            );
                          },
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              AppColors.lenderBlue.withValues(alpha: 0.18),
                              AppColors.lenderBlue.withValues(alpha: 0.00)
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const _Legend('Applications', AppColors.lenderBlue),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.18))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 10, height: 2, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Text('avg ${avg.toStringAsFixed(1)}',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning.withValues(alpha: 0.9))),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        if (_hovered >= 0 && _hovered < points.length)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _LineTooltipCard(
              point: points[_hovered],
              prev: _hovered > 0 ? points[_hovered - 1] : null,
              fullLabel: _fullLabel(points[_hovered].month),
              avg: avg,
            ),
          ),
      ],
    );
  }
}

class _LineTooltipCard extends StatelessWidget {
  final MonthlyKpiPoint point;
  final MonthlyKpiPoint? prev;
  final String fullLabel;
  final double avg;
  const _LineTooltipCard(
      {required this.point,
      required this.prev,
      required this.fullLabel,
      required this.avg});

  @override
  Widget build(BuildContext context) {
    final delta = prev == null ? null : point.applications - prev!.applications;
    final deltaPct = prev == null || prev!.applications == 0
        ? null
        : (delta! / prev!.applications * 100);
    final vsAvg = point.applications - avg;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.deepNavy,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
        border: Border.all(color: AppColors.lenderBlue.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: AppColors.lenderBlue,
                borderRadius: BorderRadius.circular(8)),
            child: Center(
              child: Text('${point.applications}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(fullLabel,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    if (delta != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: delta >= 0
                                ? AppColors.riderGreen
                                : AppColors.error,
                            borderRadius: BorderRadius.circular(99)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                delta >= 0
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded,
                                size: 11,
                                color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              '${delta >= 0 ? '+' : ''}$delta${deltaPct == null ? '' : ' (${deltaPct.toStringAsFixed(0)}%)'}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    if (delta == null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99)),
                        child: const Text('first month',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text('Released ${point.released.toCurrency}',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white.withValues(alpha: 0.82))),
                    Text('Collected ${point.collected.toCurrency}',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white.withValues(alpha: 0.82))),
                  ],
                ),
                Text(
                  vsAvg >= 0
                      ? '${vsAvg.toStringAsFixed(1)} above ${_formatAvg(avg)} avg — strong demand'
                      : '${vsAvg.abs().toStringAsFixed(1)} below ${_formatAvg(avg)} avg — softer month',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.62),
                      fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatAvg(double v) => v.toStringAsFixed(1);
}

class _MonthLineDrillSheet extends StatelessWidget {
  final MonthlyKpiPoint point;
  final MonthlyKpiPoint? prev;
  final String fullLabel;
  const _MonthLineDrillSheet(
      {required this.point, required this.prev, required this.fullLabel});

  @override
  Widget build(BuildContext context) {
    final delta = prev == null ? null : point.applications - prev!.applications;
    final deltaPct = prev == null || prev!.applications == 0
        ? null
        : (delta! / prev!.applications * 100);
    final totalApps = point.applications;
    return DraggableScrollableSheet(
      initialChildSize: 0.56,
      minChildSize: 0.42,
      maxChildSize: 0.90,
      expand: false,
      builder: (ctx, ctrl) {
        return Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            children: [
              Center(
                  child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                        color: AppColors.lenderBlue,
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                    child: Center(
                        child: Text('$totalApps',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.white))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fullLabel,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        Text(
                          delta == null
                              ? 'First month in series'
                              : '${delta >= 0 ? '+' : ''}$delta vs prev (${deltaPct?.toStringAsFixed(0) ?? '—'}%)',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: delta == null
                                  ? AppColors.textTertiary
                                  : (delta >= 0
                                      ? AppColors.riderGreen
                                      : AppColors.error)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textTertiary)),
                ],
              ),
              const Divider(height: 20, color: AppColors.divider),
              Row(
                children: [
                  Expanded(
                      child: _DrillStatCard(
                          label: 'Applications',
                          value: '$totalApps',
                          sub: 'Filed this month',
                          icon: Icons.description_rounded,
                          color: AppColors.lenderBlue)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _DrillStatCard(
                          label: 'Disbursed',
                          value: point.released.toCurrency,
                          sub: 'Funds released',
                          icon: Icons.outbox_rounded,
                          color: AppColors.deepNavy)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: _DrillStatCard(
                          label: 'Collected',
                          value: point.collected.toCurrency,
                          sub: 'Verified payments',
                          icon: Icons.savings_rounded,
                          color: AppColors.riderGreen)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DrillStatCard(
                      label: 'Net',
                      value: (point.released - point.collected).toCurrency,
                      sub: point.released >= point.collected
                          ? 'Outflow'
                          : 'Inflow',
                      icon: Icons.account_balance_wallet_rounded,
                      color: AppColors.goldDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.lenderBlue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lightbulb_rounded,
                            size: 14, color: AppColors.lenderBlue),
                        SizedBox(width: 6),
                        Text('Insight',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      totalApps == 0
                          ? 'No applications filed in $fullLabel.'
                          : delta == null
                              ? 'Baseline month — compare next months against $totalApps applications to spot demand growth.'
                              : delta > 0
                                  ? 'Demand grew by $delta (+${deltaPct?.toStringAsFixed(0) ?? '—'}%) vs previous month — funnel is expanding for $fullLabel.'
                                  : delta < 0
                                      ? 'Demand softened by ${delta.abs()} (${deltaPct?.abs().toStringAsFixed(0) ?? '—'}% down) — consider checking lead sources for $fullLabel.'
                                      : 'Flat month-on-month — stable demand at $totalApps applications.',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    try {
                      GoRouter.of(context)
                          .go(RouteConstants.hmLoanApplications);
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('View Loan Applications'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.lenderBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Revenue composition (interactive) ─────────────────────────────────────
class _RevenueBreakdown extends StatefulWidget {
  final KpiHeadManagerModel kpi;
  const _RevenueBreakdown({required this.kpi});

  @override
  State<_RevenueBreakdown> createState() => _RevenueBreakdownState();
}

class _RevenueBreakdownState extends State<_RevenueBreakdown> {
  bool _hoverInterest = false;
  bool _hoverPenalty = false;

  void _openRevenueDrill() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RevenueDrillSheet(kpi: widget.kpi),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.kpi.totalRevenue;
    if (total <= 0) {
      return const Center(
        child: Text('No revenue data yet',
            style: TextStyle(color: AppColors.textTertiary)),
      );
    }
    final interestFrac = widget.kpi.totalInterestEarned / total;
    final penaltyFrac = widget.kpi.totalPenaltiesCollected / total;

    return GestureDetector(
      onTap: _openRevenueDrill,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                MouseRegion(
                  onEnter: (_) => setState(() => _hoverInterest = true),
                  onExit: (_) => setState(() => _hoverInterest = false),
                  child: GestureDetector(
                    onTap: _openRevenueDrill,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            height: 28,
                            width: double.infinity,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeOutCubic,
                              builder: (context, t, _) => Row(
                                children: [
                                  Expanded(
                                    flex: (interestFrac * t * 1000)
                                        .round()
                                        .clamp(1, 1000),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      color: _hoverInterest
                                          ? AppColors.goldDark
                                          : AppColors.gold,
                                      child: Center(
                                        child: t > 0.9
                                            ? Text(
                                                '${(interestFrac * 100).toStringAsFixed(0)}%',
                                                style: TextStyle(
                                                    fontSize: _hoverInterest
                                                        ? 12
                                                        : 11,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.white),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: (penaltyFrac * t * 1000)
                                        .round()
                                        .clamp(1, 1000),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      color: _hoverPenalty
                                          ? AppColors.error
                                          : AppColors.error
                                              .withValues(alpha: 0.92),
                                      child: Center(
                                        child: t > 0.9 && penaltyFrac > 0.07
                                            ? Text(
                                                '${(penaltyFrac * 100).toStringAsFixed(0)}%',
                                                style: TextStyle(
                                                    fontSize:
                                                        _hoverPenalty ? 12 : 11,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.white),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Invisible hover split
                        Positioned.fill(
                          child: Row(
                            children: [
                              Expanded(
                                child: MouseRegion(
                                  onEnter: (_) => setState(() {
                                    _hoverInterest = true;
                                    _hoverPenalty = false;
                                  }),
                                  onExit: (_) =>
                                      setState(() => _hoverInterest = false),
                                ),
                              ),
                              Expanded(
                                child: MouseRegion(
                                  onEnter: (_) => setState(() {
                                    _hoverPenalty = true;
                                    _hoverInterest = false;
                                  }),
                                  onExit: (_) =>
                                      setState(() => _hoverPenalty = false),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                MouseRegion(
                  onEnter: (_) => setState(() => _hoverInterest = true),
                  onExit: (_) => setState(() => _hoverInterest = false),
                  child: GestureDetector(
                    onTap: _openRevenueDrill,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 7),
                      decoration: BoxDecoration(
                        color: _hoverInterest
                            ? AppColors.gold.withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _hoverInterest
                                ? AppColors.gold.withValues(alpha: 0.28)
                                : AppColors.border),
                      ),
                      child: _RevenueRow(
                          label: 'Interest Earned',
                          value: widget.kpi.totalInterestEarned.toCurrency,
                          color: AppColors.gold,
                          isHovered: _hoverInterest),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                MouseRegion(
                  onEnter: (_) => setState(() => _hoverPenalty = true),
                  onExit: (_) => setState(() => _hoverPenalty = false),
                  child: GestureDetector(
                    onTap: _openRevenueDrill,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 7),
                      decoration: BoxDecoration(
                        color: _hoverPenalty
                            ? AppColors.error.withValues(alpha: 0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _hoverPenalty
                                ? AppColors.error.withValues(alpha: 0.22)
                                : AppColors.border),
                      ),
                      child: _RevenueRow(
                          label: 'Penalties Collected',
                          value: widget.kpi.totalPenaltiesCollected.toCurrency,
                          color: AppColors.error,
                          isHovered: _hoverPenalty),
                    ),
                  ),
                ),
                const Divider(height: 14, color: AppColors.divider),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                      color: AppColors.deepNavy.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border)),
                  child: _RevenueRow(
                      label: 'Total Revenue',
                      value: total.toCurrency,
                      color: AppColors.deepNavy,
                      bold: true),
                ),

              ],
            ),
          ),
          if (_hoverInterest || _hoverPenalty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.deepNavy,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (_hoverInterest ? AppColors.gold : AppColors.error)
                          .withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: _hoverInterest
                                ? AppColors.gold
                                : AppColors.error,
                            borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _hoverInterest
                            ? 'Interest ${widget.kpi.totalInterestEarned.toCurrency} · ${(interestFrac * 100).toStringAsFixed(1)}% of revenue · core lending yield'
                            : 'Penalties ${widget.kpi.totalPenaltiesCollected.toCurrency} · ${(penaltyFrac * 100).toStringAsFixed(1)}% of revenue · late-fee income',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded,
                        size: 12, color: Colors.white60),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RevenueDrillSheet extends StatelessWidget {
  final KpiHeadManagerModel kpi;
  const _RevenueDrillSheet({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final total = kpi.totalRevenue;
    final interestPct =
        total == 0 ? 0.0 : kpi.totalInterestEarned / total * 100;
    final penaltyPct =
        total == 0 ? 0.0 : kpi.totalPenaltiesCollected / total * 100;
    return DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize: 0.42,
      maxChildSize: 0.88,
      expand: false,
      builder: (ctx, ctrl) {
        return Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            children: [
              Center(
                  child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.payments_rounded, color: AppColors.deepNavy),
                  SizedBox(width: 8),
                  Text('Revenue Breakdown',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  'Total ${total.toCurrency} · interest-led earnings with penalty overlay',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const Divider(height: 20, color: AppColors.divider),
              _RevenueDetailRow(
                  label: 'Interest Earned',
                  value: kpi.totalInterestEarned.toCurrency,
                  pct: interestPct,
                  color: AppColors.gold,
                  icon: Icons.trending_up_rounded,
                  desc:
                      'Yield from active / completed loans — rate × term × principal.'),
              const SizedBox(height: 10),
              _RevenueDetailRow(
                  label: 'Penalties Collected',
                  value: kpi.totalPenaltiesCollected.toCurrency,
                  pct: penaltyPct,
                  color: AppColors.error,
                  icon: Icons.gavel_rounded,
                  desc:
                      'Late-payment & overdue penalties — collected via verified payments.'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.deepNavy.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: AppColors.deepNavy,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.account_balance_wallet_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Revenue',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textTertiary)),
                          Text(total.toCurrency,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.deepNavy)),
                          Text(
                              '${kpi.totalInterestEarned.toCurrency} interest + ${kpi.totalPenaltiesCollected.toCurrency} penalties',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    try {
                      GoRouter.of(context).go(RouteConstants.hmReports);
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.assessment_rounded, size: 16),
                  label: const Text('View Reports'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RevenueDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final double pct;
  final Color color;
  final IconData icon;
  final String desc;
  const _RevenueDetailRow(
      {required this.label,
      required this.value,
      required this.pct,
      required this.color,
      required this.icon,
      required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(7)),
                  child: Icon(icon, size: 14, color: color)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary))),
              Text('${pct.toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 4),
          Text(desc,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(color))),
        ],
      ),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;
  final bool isHovered;
  const _RevenueRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
    this.isHovered = false,
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
            boxShadow: isHovered
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.28),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ]
                : null,
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
              fontWeight: bold
                  ? FontWeight.w800
                  : (isHovered ? FontWeight.w700 : FontWeight.w500),
              color: isHovered ? color : AppColors.textSecondary,
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
              fontWeight: FontWeight.w800,
              color: bold ? AppColors.textPrimary : color,
            ),
          ),
        ),
        if (isHovered) ...[
          const SizedBox(width: 6),
          Icon(Icons.open_in_new_rounded,
              size: 12, color: color.withValues(alpha: 0.7)),
        ],
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

class _LegendInteractive extends StatelessWidget {
  final String label;
  final Color color;
  final bool isHovered;
  const _LegendInteractive(this.label, this.color, {this.isHovered = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isHovered ? color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color:
                isHovered ? color.withValues(alpha: 0.18) : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
            style: TextStyle(
                fontSize: 11,
                fontWeight: isHovered ? FontWeight.w700 : FontWeight.w500,
                color: isHovered ? color : AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
