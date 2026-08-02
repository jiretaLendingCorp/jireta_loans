// lib/presentation/features/lender/dashboard/screens/lender_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/animated/count_up_animation.dart';
import '../providers/lender_dashboard_provider.dart';

class LenderDashboardScreen extends ConsumerStatefulWidget {
  const LenderDashboardScreen({super.key});

  @override
  ConsumerState<LenderDashboardScreen> createState() =>
      _LenderDashboardScreenState();
}

class _LenderDashboardScreenState extends ConsumerState<LenderDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;

  static const _riderNavItems = [
    MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard,
    ),
    MobileNavItem(
      icon: Icons.account_balance_outlined,
      activeIcon: Icons.account_balance,
      label: 'My Loan',
      route: RouteConstants.lenderLoans,
    ),
    MobileNavItem(
      icon: Icons.payment_outlined,
      activeIcon: Icons.payment,
      label: 'Payments',
      route: RouteConstants.lenderPayments,
    ),
    MobileNavItem(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      label: 'Alerts',
      route: RouteConstants.lenderNotifications,
    ),
    MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderDashboardProvider);

    return MobileScaffold(
      title: 'My Account',
      accentColor: AppColors.lenderPurple,
      navItems: _riderNavItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(lenderDashboardProvider.notifier).load(),
              color: AppColors.lenderPurple,
              child: FadeTransition(
                opacity: _fadeCtrl,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WelcomeBanner(kpi: state.kpi),
                      const SizedBox(height: 20),
                      _QuickActions(context: context),
                      const SizedBox(height: 20),
                      const _SectionLabel('Account Summary'),
                      const SizedBox(height: 12),
                      _KpiGrid(kpi: state.kpi),
                      const SizedBox(height: 20),
                      if (state.error != null) _ErrorBanner(state.error!),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  final dynamic kpi;
  const _WelcomeBanner({required this.kpi});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.lenderPurple, AppColors.lenderPurpleLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.lenderPurple.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Jireta Loans',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Outstanding Balance',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          CountUpAnimation(
            value: (kpi?.remainingBalance ?? 0).toDouble(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              fontFamily: 'PlayfairDisplay',
            ),
            prefix: '₱',
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final BuildContext context;
  const _QuickActions({required this.context});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionBtn(
            icon: Icons.add_circle_outline,
            label: 'Apply Loan',
            color: AppColors.lenderPurple,
            onTap: () => context.push(RouteConstants.lenderLoans),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionBtn(
            icon: Icons.payment_outlined,
            label: 'Pay Now',
            color: AppColors.success,
            onTap: () => context.push(RouteConstants.lenderPayments),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionBtn(
            icon: Icons.receipt_long_outlined,
            label: 'Schedule',
            color: AppColors.info,
            onTap: () => context.push(RouteConstants.lenderPayments),
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final dynamic kpi;
  const _KpiGrid({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final items = [
      _KpiItem('Applications', kpi?.totalApplications ?? 0,
          Icons.description_outlined, AppColors.lenderPurple, false),
      _KpiItem('Approved', kpi?.totalApproved ?? 0, Icons.check_circle_outline,
          AppColors.success, false),
      _KpiItem('Rejected', kpi?.totalRejected ?? 0, Icons.cancel_outlined,
          AppColors.error, false),
      _KpiItem('Active', kpi?.totalActive ?? 0, Icons.trending_up,
          AppColors.warning, false),
      _KpiItem('Completed', kpi?.totalCompleted ?? 0, Icons.done_all,
          AppColors.info, false),
      _KpiItem('Total Borrowed', kpi?.totalBorrowed ?? 0, Icons.account_balance,
          AppColors.lenderPurple, true),
      _KpiItem('Total Paid', kpi?.totalPaid ?? 0, Icons.payments,
          AppColors.success, true),
      _KpiItem('Interest Paid', kpi?.totalInterestPaid ?? 0, Icons.percent,
          AppColors.warning, true),
      _KpiItem('Penalties Paid', kpi?.totalPenaltiesPaid ?? 0,
          Icons.warning_outlined, AppColors.error, true),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _KpiCard(item: items[i]),
    );
  }
}

class _KpiItem {
  final String label;
  final num value;
  final IconData icon;
  final Color color;
  final bool isCurrency;
  const _KpiItem(
      this.label, this.value, this.icon, this.color, this.isCurrency);
}

class _KpiCard extends StatelessWidget {
  final _KpiItem item;
  const _KpiCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: item.color, size: 18),
          ),
          const SizedBox(height: 8),
          CountUpAnimation(
            value: item.value.toDouble(),
            style: TextStyle(
              fontSize: item.isCurrency ? 11 : 18,
              fontWeight: FontWeight.bold,
              color: item.color,
            ),
            prefix: item.isCurrency ? '₱' : '',
            compact: item.isCurrency,
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  const _ErrorBanner(this.error);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
