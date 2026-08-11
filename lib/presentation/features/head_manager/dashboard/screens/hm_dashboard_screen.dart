// lib/presentation/features/head_manager/dashboard/screens/hm_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../data/models/kpi_head_manager_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/hm_dashboard_provider.dart';

class HmDashboardScreen extends ConsumerStatefulWidget {
  const HmDashboardScreen({super.key});

  @override
  ConsumerState<HmDashboardScreen> createState() => _HmDashboardScreenState();
}

class _HmDashboardScreenState extends ConsumerState<HmDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(hmDashboardProvider);

    return WebScaffold(
      title: 'Dashboard',
      actions: [
        IconButton(
          onPressed: () => ref.read(hmDashboardProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          tooltip: 'Refresh',
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
                    _buildWelcomeHeader(),
                    const SizedBox(height: 24),
                    _buildQuickActions(context),
                    const SizedBox(height: 24),
                    _buildSectionTitle('User Statistics'),
                    const SizedBox(height: 12),
                    _buildUserStatsGrid(dashState.kpi),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Loan Overview'),
                    const SizedBox(height: 12),
                    _buildLoanStatsGrid(dashState.kpi),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Financial Metrics'),
                    const SizedBox(height: 12),
                    _buildFinancialGrid(dashState.kpi),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Operational Metrics'),
                    const SizedBox(height: 12),
                    _buildOperationalGrid(dashState.kpi),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
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

  Widget _buildWelcomeHeader() {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.deepNavy, AppColors.navyLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
            ),
            child: const Icon(
              Icons.account_balance,
              color: AppColors.gold,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, Head Manager',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFamily: 'PlayfairDisplay',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Jireta Loans & Credit Corp 1966 — Enterprise Dashboard',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.riderGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'System Online',
                  style: TextStyle(fontSize: 12, color: AppColors.gold),
                ),
              ],
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
        () => context.go(RouteConstants.hmInOffice),
      ),
      _QuickAction(
        Icons.person_add_outlined,
        'Add Employee',
        AppColors.deepNavy,
        () => context.go(RouteConstants.hmEmployees),
      ),
      _QuickAction(
        Icons.description_outlined,
        'Loan Applications',
        AppColors.warning,
        () => context.go(RouteConstants.hmLoanApplications),
      ),
      _QuickAction(
        Icons.verified_user_outlined,
        'KYC Review',
        AppColors.info,
        () => context.go(RouteConstants.hmKyc),
      ),
      _QuickAction(
        Icons.assessment_outlined,
        'Generate Report',
        AppColors.riderGreen,
        () => context.go(RouteConstants.hmReports),
      ),
    ];

    return Row(
      children: actions
          .map(
            (a) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: actions.indexOf(a) < actions.length - 1 ? 12 : 0,
                ),
                child: _QuickActionCard(action: a),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildUserStatsGrid(KpiHeadManagerModel kpi) {
    return _buildGridRow([
      _KpiCard(
        label: 'Total Employees',
        value: kpi.totalEmployees.toString(),
        icon: Icons.people_outline,
        color: AppColors.deepNavy,
        isCurrency: false,
      ),
      _KpiCard(
        label: 'Total Riders',
        value: kpi.totalRiders.toString(),
        icon: Icons.delivery_dining_outlined,
        color: AppColors.riderGreen,
        isCurrency: false,
      ),
      _KpiCard(
        label: 'Total Lenders',
        value: kpi.totalLenders.toString(),
        icon: Icons.person_outline,
        color: AppColors.lenderPurple,
        isCurrency: false,
      ),
      _KpiCard(
        label: 'Pending KYC',
        value: kpi.totalPendingKyc.toString(),
        icon: Icons.verified_user_outlined,
        color: AppColors.warning,
        isCurrency: false,
      ),
    ]);
  }

  Widget _buildLoanStatsGrid(KpiHeadManagerModel kpi) {
    return Column(
      children: [
        _buildGridRow([
          _KpiCard(
            label: 'Total Applications',
            value: kpi.totalLoanApplications.toString(),
            icon: Icons.description_outlined,
            color: AppColors.info,
            isCurrency: false,
          ),
          _KpiCard(
            label: 'Approved Loans',
            value: kpi.totalApprovedLoans.toString(),
            icon: Icons.check_circle_outline,
            color: AppColors.riderGreen,
            isCurrency: false,
          ),
          _KpiCard(
            label: 'Active Loans',
            value: kpi.totalActiveLoans.toString(),
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.deepNavy,
            isCurrency: false,
          ),
          _KpiCard(
            label: 'Completed Loans',
            value: kpi.totalCompletedLoans.toString(),
            icon: Icons.done_all_outlined,
            color: AppColors.info,
            isCurrency: false,
          ),
        ]),
        const SizedBox(height: 12),
        _buildGridRow([
          _KpiCard(
            label: 'Rejected Loans',
            value: kpi.totalRejectedLoans.toString(),
            icon: Icons.cancel_outlined,
            color: AppColors.error,
            isCurrency: false,
          ),
          _KpiCard(
            label: 'Overdue Loans',
            value: kpi.totalOverdueLoans.toString(),
            icon: Icons.warning_outlined,
            color: AppColors.statusOverdue,
            isCurrency: false,
          ),
          _KpiCard(
            label: 'CI Assignments',
            value: kpi.totalCiAssignments.toString(),
            icon: Icons.search_outlined,
            color: AppColors.lenderPurple,
            isCurrency: false,
          ),
          _KpiCard(
            label: 'Collections',
            value: kpi.totalCollectionTransactions.toString(),
            icon: Icons.local_shipping_outlined,
            color: AppColors.riderGreen,
            isCurrency: false,
          ),
        ]),
      ],
    );
  }

  Widget _buildFinancialGrid(KpiHeadManagerModel kpi) {
    return Column(
      children: [
        _buildGridRow([
          _KpiCard(
            label: 'Amount Released',
            value: kpi.totalLoanAmountReleased.toCurrencyShort,
            icon: Icons.payments_outlined,
            color: AppColors.deepNavy,
            isCurrency: true,
          ),
          _KpiCard(
            label: 'Amount Collected',
            value: kpi.totalAmountCollected.toCurrencyShort,
            icon: Icons.savings_outlined,
            color: AppColors.riderGreen,
            isCurrency: true,
          ),
          _KpiCard(
            label: 'Outstanding Balance',
            value: kpi.totalOutstandingBalance.toCurrencyShort,
            icon: Icons.account_balance_outlined,
            color: AppColors.warning,
            isCurrency: true,
          ),
          _KpiCard(
            label: 'Interest Earned',
            value: kpi.totalInterestEarned.toCurrencyShort,
            icon: Icons.trending_up_outlined,
            color: AppColors.gold,
            isCurrency: true,
          ),
        ]),
        const SizedBox(height: 12),
        _buildGridRow([
          _KpiCard(
            label: 'Penalties Collected',
            value: kpi.totalPenaltiesCollected.toCurrencyShort,
            icon: Icons.gavel_outlined,
            color: AppColors.error,
            isCurrency: true,
          ),
          _KpiCard(
            label: 'Total Revenue',
            value: kpi.totalRevenue.toCurrencyShort,
            icon: Icons.monetization_on_outlined,
            color: AppColors.riderGreen,
            isCurrency: true,
          ),
          const _EmptyCard(),
          const _EmptyCard(),
        ]),
      ],
    );
  }

  Widget _buildOperationalGrid(KpiHeadManagerModel kpi) {
    return _buildGridRow([
      _KpiCard(
        label: 'Report Exports',
        value: kpi.totalReportExports.toString(),
        icon: Icons.assessment_outlined,
        color: AppColors.info,
        isCurrency: false,
      ),
      const _EmptyCard(),
      const _EmptyCard(),
      const _EmptyCard(),
    ]);
  }

  Widget _buildGridRow(List<Widget> cards) {
    return Row(
      children: cards
          .asMap()
          .entries
          .map(
            (e) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: e.key > 0 ? 12 : 0),
                child: e.value,
              ),
            ),
          )
          .toList(),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: widget.action.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: _hover
                  ? widget.action.color.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
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
                    borderRadius: BorderRadius.circular(8),
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
                      color: _hover
                          ? widget.action.color
                          : AppColors.textPrimary,
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
      ),
    );
  }
}

class _KpiCard extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isCurrency;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isCurrency,
  });

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _scaleAnim = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hover ? widget.color.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? widget.color.withValues(alpha: 0.3) : AppColors.border,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    const BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.icon, size: 18, color: widget.color),
                  ),
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: widget.color,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) => const SizedBox();
}
