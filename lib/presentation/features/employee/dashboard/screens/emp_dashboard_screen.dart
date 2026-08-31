// lib/presentation/features/employee/dashboard/screens/emp_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/emp_dashboard_provider.dart';

class EmpDashboardScreen extends ConsumerStatefulWidget {
  const EmpDashboardScreen({super.key});

  @override
  ConsumerState<EmpDashboardScreen> createState() => _EmpDashboardScreenState();
}

class _EmpDashboardScreenState extends ConsumerState<EmpDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(empDashboardProvider);

    return WebScaffold(
      title: 'Dashboard',
      actions: [
        IconButton(
          onPressed: () => ref.read(empDashboardProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          tooltip: 'Refresh',
        ),
      ],
      body: dashState.isLoading
          ? _buildShimmer()
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(empDashboardProvider.notifier).refresh(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildQuickActions(context),
                    const SizedBox(height: 24),
                    _buildSectionTitle('My Performance Metrics'),
                    const SizedBox(height: 12),
                    _buildKpiGrid(dashState),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildShimmer() {
    // Scrollable so short viewports never get a bottom-overflow error while
    // the (fixed-height) skeleton rows are showing.
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

  Widget _buildKpiGrid(EmpDashboardState dashState) {
    final kpi = dashState.kpi;
    return Column(
      children: [
        _buildGridRow([
          _KpiCard(
            label: 'Lenders Managed',
            value: kpi.totalLendersManaged.toString(),
            icon: Icons.people_outline,
            color: AppColors.lenderBlue,
          ),
          _KpiCard(
            label: 'Applications Processed',
            value: kpi.totalApplicationsProcessed.toString(),
            icon: Icons.description_outlined,
            color: AppColors.deepNavy,
          ),
          _KpiCard(
            label: 'Approved Loans',
            value: kpi.totalApprovedLoans.toString(),
            icon: Icons.check_circle_outline,
            color: AppColors.riderGreen,
          ),
          _KpiCard(
            label: 'Rejected Loans',
            value: kpi.totalRejectedLoans.toString(),
            icon: Icons.cancel_outlined,
            color: AppColors.error,
          ),
        ]),
        const SizedBox(height: 12),
        _buildGridRow([
          _KpiCard(
            label: 'Active Loans',
            value: kpi.totalActiveLoans.toString(),
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.info,
          ),
          _KpiCard(
            label: 'Completed Loans',
            value: kpi.totalCompletedLoans.toString(),
            icon: Icons.done_all_outlined,
            color: AppColors.riderGreen,
          ),
          _KpiCard(
            label: 'Collections Managed',
            value: kpi.totalCollectionsManaged.toString(),
            icon: Icons.local_shipping_outlined,
            color: AppColors.warning,
          ),
          const _EmptyCard(),
        ]),
      ],
    );
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
              .where((card) => card is! _EmptyCard)
              .map((card) => SizedBox(width: cardWidth, child: card))
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
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
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

class _KpiCard extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
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
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
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
              color: _hover
                  ? widget.color.withValues(alpha: 0.3)
                  : AppColors.border,
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
                      color: Color(0x05000000),
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
