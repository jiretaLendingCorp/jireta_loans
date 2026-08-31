// lib/presentation/features/head_manager/dashboard/screens/hm_dashboard_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/kpi_head_manager_model.dart';
import '../../../../shared/widgets/animated/count_up_animation.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/hm_dashboard_provider.dart';
import '../widgets/hm_analytics_panel.dart';

class HmDashboardScreen extends ConsumerStatefulWidget {
  const HmDashboardScreen({super.key});

  @override
  ConsumerState<HmDashboardScreen> createState() => _HmDashboardScreenState();
}

class _HmDashboardScreenState extends ConsumerState<HmDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(hmDashboardProvider);

    return WebScaffold(
      title: 'Dashboard',
      actions: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: IconButton(
            onPressed: () => ref.read(hmDashboardProvider.notifier).refresh(),
            icon: dashState.isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
            tooltip: 'Refresh',
          ),
        ),
      ],
      body: dashState.isLoading
          ? _buildShimmer()
          : RefreshIndicator(
              onRefresh: () => ref.read(hmDashboardProvider.notifier).refresh(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Single portfolio donut — full width, clean spacing
                    _Entrance(child: HmAnalyticsPanel(kpi: dashState.kpi)),
                    const SizedBox(height: 28),
                    _buildSectionTitle(
                      Icons.people_rounded,
                      'User Statistics',
                      'Staff and lender counts across the branch',
                    ),
                    const SizedBox(height: 14),
                    _buildUserStatsGrid(dashState.kpi),
                    const SizedBox(height: 28),
                    _buildSectionTitle(
                      Icons.account_balance_wallet_rounded,
                      'Financial Metrics',
                      'Money in, money out and everything in between',
                    ),
                    const SizedBox(height: 14),
                    _buildFinancialGrid(dashState.kpi),
                    const SizedBox(height: 28),
                    _buildSectionTitle(
                      Icons.description_rounded,
                      'Loan Overview',
                      'Loan portfolio at a glance',
                    ),
                    const SizedBox(height: 14),
                    _buildLoanStatsGrid(dashState.kpi),
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
          const ShimmerLoader(height: 320),
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
            borderRadius: BorderRadius.circular(11),
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

  Widget _buildUserStatsGrid(KpiHeadManagerModel kpi) {
    return _buildGridRow([
      _KpiCard(label: 'Total Employees', value: kpi.totalEmployees.toDouble(), icon: Icons.people_rounded, color: AppColors.deepNavy, isCurrency: false),
      _KpiCard(label: 'Total Riders', value: kpi.totalRiders.toDouble(), icon: Icons.delivery_dining_rounded, color: AppColors.riderGreen, isCurrency: false),
      _KpiCard(label: 'Total Lenders', value: kpi.totalLenders.toDouble(), icon: Icons.person_rounded, color: AppColors.lenderBlue, isCurrency: false),
      _KpiCard(label: 'Pending Account Upgrade', value: kpi.totalPendingAccountUpgrade.toDouble(), icon: Icons.verified_user_rounded, color: AppColors.warning, isCurrency: false),
    ]);
  }

  Widget _buildLoanStatsGrid(KpiHeadManagerModel kpi) {
    // Single Wrap so 8 cards flow as 4+4 on desktop, 3+3+2 on tablet, no isolated card
    return _buildGridRow([
      _KpiCard(label: 'Total Applications', value: kpi.totalLoanApplications.toDouble(), icon: Icons.description_rounded, color: AppColors.info, isCurrency: false),
      _KpiCard(label: 'Approved Loans', value: kpi.totalApprovedLoans.toDouble(), icon: Icons.check_circle_rounded, color: AppColors.riderGreen, isCurrency: false),
      _KpiCard(label: 'Active Loans', value: kpi.totalActiveLoans.toDouble(), icon: Icons.account_balance_wallet_rounded, color: AppColors.deepNavy, isCurrency: false),
      _KpiCard(label: 'Completed Loans', value: kpi.totalCompletedLoans.toDouble(), icon: Icons.done_all_rounded, color: AppColors.info, isCurrency: false),
      _KpiCard(label: 'Rejected Loans', value: kpi.totalRejectedLoans.toDouble(), icon: Icons.cancel_rounded, color: AppColors.error, isCurrency: false),
      _KpiCard(label: 'Overdue Loans', value: kpi.totalOverdueLoans.toDouble(), icon: Icons.warning_rounded, color: AppColors.statusOverdue, isCurrency: false),
      _KpiCard(label: 'CI Assignments', value: kpi.totalCiAssignments.toDouble(), icon: Icons.search_rounded, color: AppColors.lenderBlue, isCurrency: false),
      _KpiCard(label: 'Collections', value: kpi.totalCollectionTransactions.toDouble(), icon: Icons.delivery_dining_rounded, color: AppColors.riderGreen, isCurrency: false),
    ]);
  }

  Widget _buildFinancialGrid(KpiHeadManagerModel kpi) {
    // Single Wrap for 6 cards so no 4+2 split leaves isolated cards
    return _buildGridRow([
      _KpiCard(label: 'Amount Released', value: kpi.totalLoanAmountReleased, icon: Icons.payments_rounded, color: AppColors.deepNavy, isCurrency: true),
      _KpiCard(label: 'Amount Collected', value: kpi.totalAmountCollected, icon: Icons.savings_rounded, color: AppColors.riderGreen, isCurrency: true),
      _KpiCard(label: 'Outstanding Balance', value: kpi.totalOutstandingBalance, icon: Icons.account_balance_rounded, color: AppColors.warning, isCurrency: true),
      _KpiCard(label: 'Interest Earned', value: kpi.totalInterestEarned, icon: Icons.trending_up_rounded, color: AppColors.goldDark, isCurrency: true),
      _KpiCard(label: 'Penalties Collected', value: kpi.totalPenaltiesCollected, icon: Icons.gavel_rounded, color: AppColors.error, isCurrency: true),
      _KpiCard(label: 'Total Revenue', value: kpi.totalRevenue, icon: LucideIcons.philippinePeso, color: AppColors.riderGreen, isCurrency: true),
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
        final cardWidth = (constraints.maxWidth - (spacing * (columns - 1))) / columns;
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

class _KpiCard extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool isCurrency;

  const _KpiCard({required this.label, required this.value, required this.icon, required this.color, required this.isCurrency});

  @override
  Widget build(BuildContext context) {
    return _KpiCardBody(label: label, value: value, icon: icon, color: color, isCurrency: isCurrency);
  }
}

class _KpiCardBody extends StatefulWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool isCurrency;

  const _KpiCardBody({required this.label, required this.value, required this.icon, required this.color, required this.isCurrency});

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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hover ? color.withValues(alpha: 0.32) : AppColors.border),
          boxShadow: _hover
              ? [BoxShadow(color: color.withValues(alpha: 0.14), blurRadius: 16, offset: const Offset(0, 6))]
              : const [BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.65)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: Icon(widget.icon, size: 19, color: Colors.white),
                ),
                const Spacer(),
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color.withValues(alpha: 0.55), shape: BoxShape.circle)),
              ],
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: widget.isCurrency
                  ? CountUpAnimation(value: widget.value, prefix: '₱', decimalPlaces: 2, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.4))
                  : CountUpAnimation(value: widget.value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.4)),
            ),
            const SizedBox(height: 6),
            Text(widget.label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => Container(
                height: 3,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), gradient: LinearGradient(colors: [color.withValues(alpha: 0.5), color.withValues(alpha: 0.15)])),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: t,
                  child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.5)]))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fade + slide + scale entrance used across dashboard sections.
class _Entrance extends StatefulWidget {
  final Widget child;
  final int delay;
  const _Entrance({required this.child, this.delay = 0});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  late final Animation<double> _scale;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _offset = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved);
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
    return FadeTransition(opacity: _opacity, child: SlideTransition(position: _offset, child: ScaleTransition(scale: _scale, child: widget.child)));
  }
}
