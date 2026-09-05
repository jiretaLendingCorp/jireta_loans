// lib/presentation/features/employee/dashboard/screens/emp_dashboard_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/animated/count_up_animation.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/emp_dashboard_provider.dart';

class EmpDashboardScreen extends ConsumerStatefulWidget {
  const EmpDashboardScreen({super.key});

  @override
  ConsumerState<EmpDashboardScreen> createState() => _EmpDashboardScreenState();
}

class _EmpDashboardScreenState extends ConsumerState<EmpDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(empDashboardProvider);
    final notifier = ref.read(empDashboardProvider.notifier);

    return WebScaffold(
      title: 'Dashboard',
      actions: [
        // Month picker — monthly dashboard (tulad ng head manager)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.border)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: dashState.selectedMonth,
              icon: const Icon(Icons.calendar_month_rounded,
                  size: 18, color: AppColors.deepNavy),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy),
              isDense: true,
              items: EmpDashboardNotifier.availableMonths().map((m) {
                return DropdownMenuItem(
                    value: m,
                    child: Text(EmpDashboardNotifier.monthLabel(m)));
              }).toList(),
              onChanged: (v) {
                if (v != null) notifier.setMonth(v);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.border),
          ),
          child: IconButton(
            onPressed: () => notifier.refresh(),
            icon: dashState.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded,
                    color: AppColors.textSecondary, size: 20),
            tooltip: 'Refresh',
          ),
        ),
      ],
      body: dashState.isLoading
          ? _buildShimmer()
          : RefreshIndicator(
              onRefresh: () => notifier.refresh(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildQuickActions(context),
                    const SizedBox(height: 28),
                    _buildSectionTitle(
                      Icons.people_rounded,
                      'My Performance Metrics — ${EmpDashboardNotifier.monthLabel(dashState.selectedMonth)}',
                      'Your activity within the selected month',
                    ),
                    const SizedBox(height: 14),
                    _buildPerformanceGrid(dashState),
                    const SizedBox(height: 28),
                    _buildSectionTitle(
                      Icons.account_balance_wallet_rounded,
                      'Loan Portfolio — ${EmpDashboardNotifier.monthLabel(dashState.selectedMonth)}',
                      'Loans you handled in the selected month',
                    ),
                    const SizedBox(height: 14),
                    _buildPortfolioGrid(dashState),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildShimmer() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const ShimmerLoader(height: 100),
          const SizedBox(height: 16),
          Row(
            children: List.generate(
              4,
              (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i > 0 ? 16 : 0),
                  child: const ShimmerLoader(height: 120),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(
              4,
              (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i > 0 ? 16 : 0),
                  child: const ShimmerLoader(height: 120),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _QuickAction(
        Icons.storefront_outlined,
        'In-Office',
        AppColors.deepNavy,
        () => context.go(RouteConstants.empInOffice),
      ),
      _QuickAction(
        Icons.person_add_outlined,
        'Create Lender',
        AppColors.lenderBlue,
        () => context.go(RouteConstants.empLenders),
      ),
      _QuickAction(
        Icons.description_outlined,
        'Loan Records',
        AppColors.warning,
        () => context.go(RouteConstants.empLoans),
      ),
      _QuickAction(
        Icons.verified_user_outlined,
        'Lender Account Upgrade',
        AppColors.info,
        () => context.go(RouteConstants.empAccountUpgrade),
      ),
      _QuickAction(
        Icons.payments_outlined,
        'Record Payment',
        AppColors.riderGreen,
        () => context.go(RouteConstants.empPayments),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 900 ? 5 : constraints.maxWidth >= 600 ? 3 : 2;
        const spacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: actions
              .map((a) => SizedBox(
                    width: cardWidth,
                    child: _QuickActionCard(action: a),
                  ))
              .toList(),
        );
      },
    );
  }

  // ── Head-manager style section header: gold gradient icon + title/subtitle + divider ──
  Widget _buildSectionTitle(
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.gold, AppColors.goldDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.zero,
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.32),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const Expanded(
          child: Divider(color: AppColors.divider, height: 1),
        ),
      ],
    );
  }

  Widget _buildPerformanceGrid(EmpDashboardState dashState) {
    final kpi = dashState.kpi;
    // Single Wrap so cards flow as 4 on desktop, no isolated card
    return _buildGridRow([
      _KpiCard(
          label: 'Lenders Managed',
          value: kpi.totalLendersManaged.toDouble(),
          icon: Icons.people_outline,
          color: AppColors.lenderBlue),
      _KpiCard(
          label: 'Applications Processed',
          value: kpi.totalApplicationsProcessed.toDouble(),
          icon: Icons.description_outlined,
          color: AppColors.deepNavy),
      _KpiCard(
          label: 'Approved Loans',
          value: kpi.totalApprovedLoans.toDouble(),
          icon: Icons.check_circle_rounded,
          color: AppColors.riderGreen),
      _KpiCard(
          label: 'Rejected Loans',
          value: kpi.totalRejectedLoans.toDouble(),
          icon: Icons.cancel_rounded,
          color: AppColors.error),
    ]);
  }

  Widget _buildPortfolioGrid(EmpDashboardState dashState) {
    final kpi = dashState.kpi;
    return _buildGridRow([
      _KpiCard(
          label: 'Active Loans',
          value: kpi.totalActiveLoans.toDouble(),
          icon: Icons.account_balance_wallet_rounded,
          color: AppColors.info),
      _KpiCard(
          label: 'Completed Loans',
          value: kpi.totalCompletedLoans.toDouble(),
          icon: Icons.done_all_rounded,
          color: AppColors.riderGreen),
      _KpiCard(
          label: 'Collections Managed',
          value: kpi.totalCollectionsManaged.toDouble(),
          icon: Icons.local_shipping_outlined,
          color: AppColors.warning),
    ]);
  }

  Widget _buildGridRow(List<Widget> cards) {
    const spacing = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1200
            ? 4
            : constraints.maxWidth >= 700
                ? 3
                : constraints.maxWidth >= 480
                    ? 2
                    : 1;
        final cardWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .asMap()
              .entries
              .map((e) => SizedBox(
                    width: cardWidth,
                    child: _Entrance(delay: 80 + e.key * 55, child: e.value),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.label, this.color, this.onTap);
}

class _QuickActionCard extends StatefulWidget {
  final _QuickAction action;
  const _QuickActionCard({required this.action});

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.action.onTap,
        borderRadius: BorderRadius.zero,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: _hover
                ? widget.action.color.withValues(alpha: 0.08)
                : Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: _hover
                  ? widget.action.color.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: widget.action.color.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.action.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.zero,
                ),
                child: Icon(
                  widget.action.icon,
                  size: 18,
                  color: widget.action.color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.action.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _hover ? widget.action.color : AppColors.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 12,
                color: _hover ? widget.action.color : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Head-manager style KPI card: grey header strip + CountUp value ──
class _KpiCard extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;

  const _KpiCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return _KpiCardBody(
        label: label, value: value, icon: icon, color: color);
  }
}

class _KpiCardBody extends StatefulWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;

  const _KpiCardBody(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  State<_KpiCardBody> createState() => _KpiCardBodyState();
}

class _KpiCardBodyState extends State<_KpiCardBody> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(
              color: _hover
                  ? color.withValues(alpha: 0.32)
                  : AppColors.border),
          boxShadow: _hover
              ? [
                  BoxShadow(
                      color: color.withValues(alpha: 0.14),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ]
              : const [
                  BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 6,
                      offset: Offset(0, 2))
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grey header strip (gaya ng head manager / loan details cards)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF5C6370),
                border: Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Icon(widget.icon, size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle)),
                ],
              ),
            ),
            // Body — value
            Padding(
              padding: const EdgeInsets.all(16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: CountUpAnimation(
                    value: widget.value,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: -0.4)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fade + slide + scale entrance used across dashboard sections (tulad ng head manager).
class _Entrance extends StatefulWidget {
  final Widget child;
  final int delay;
  const _Entrance({required this.child, this.delay = 0});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  late final Animation<double> _scale;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _offset =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(curved);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(curved);
    _timer = Timer(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
            position: _offset,
            child: ScaleTransition(scale: _scale, child: widget.child)));
  }
}
