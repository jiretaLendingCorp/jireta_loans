// lib/presentation/features/lender/dashboard/screens/lender_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/kpi_lender_model.dart';
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
                      _KycStatusCard(kpi: state.kpi),
                      const SizedBox(height: 20),
                      _QuickActions(context: context),
                      const SizedBox(height: 20),
                      _MyLoansOverview(kpi: state.kpi),
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

class _KycStatusCard extends StatelessWidget {
  final KpiLenderModel kpi;
  const _KycStatusCard({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final status = kpi.kycStatus;
    final isApproved = status == 'verified' || status == 'approved';
    final isRejected = status == 'rejected';
    final isSubmitted = status == 'submitted' || status == 'pending';

    final Color bg;
    final Color fg;
    final IconData icon;
    final String title;
    final String subtitle;
    final String actionLabel;
    final VoidCallback? onAction;

    if (isApproved) {
      bg = AppColors.successLight;
      fg = AppColors.success;
      icon = Icons.verified_user_outlined;
      title = 'KYC Verified';
      subtitle = 'Your account has been fully verified.';
      actionLabel = '';
      onAction = null;
    } else if (isRejected) {
      bg = AppColors.errorLight;
      fg = AppColors.error;
      icon = Icons.gpp_bad_outlined;
      title = 'KYC Rejected';
      subtitle = 'Your KYC submission needs attention. Please resubmit.';
      actionLabel = 'Resubmit';
      onAction = () => context.push(RouteConstants.lenderKyc);
    } else if (isSubmitted) {
      bg = AppColors.warningLight;
      fg = AppColors.warning;
      icon = Icons.hourglass_top_rounded;
      title = 'KYC Under Review';
      subtitle = 'Your documents are being reviewed. We\'ll notify you once verified.';
      actionLabel = 'View Status';
      onAction = () => context.push(RouteConstants.lenderKycStatus);
    } else {
      bg = AppColors.warningLight;
      fg = AppColors.warning;
      icon = Icons.verified_user_outlined;
      title = 'Account Not Verified';
      subtitle = 'Complete your KYC to start borrowing with Jireta Loans.';
      actionLabel = 'Verify Now';
      onAction = () => context.push(RouteConstants.lenderKyc);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: fg, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onAction != null && actionLabel.isNotEmpty)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: fg),
              child: Text(actionLabel),
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

class _MyLoansOverview extends StatelessWidget {
  final dynamic kpi;
  const _MyLoansOverview({required this.kpi});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('My Loans'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.lenderPurple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long_outlined,
                        color: AppColors.lenderPurple, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Applications Submitted',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text(
                          '${kpi?.totalApplications ?? 0}',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  _MiniBadge(label: 'Active', value: kpi?.totalActive ?? 0),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _OverviewMetric(
                      label: 'Approved',
                      value: kpi?.totalApproved ?? 0,
                      color: AppColors.success,
                    ),
                  ),
                  Expanded(
                    child: _OverviewMetric(
                      label: 'Completed',
                      value: kpi?.totalCompleted ?? 0,
                      color: AppColors.info,
                    ),
                  ),
                  Expanded(
                    child: _OverviewMetric(
                      label: 'Rejected',
                      value: kpi?.totalRejected ?? 0,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      color: AppColors.lenderPurple, size: 18),
                  const SizedBox(width: 6),
                  const Text('Total Paid',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const Spacer(),
                  CountUpAnimation(
                    value: (kpi?.totalPaid ?? 0).toDouble(),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success),
                    prefix: '₱',
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final num value;
  const _MiniBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.lenderPurple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label · $value',
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.lenderPurple),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  final String label;
  final num value;
  final Color color;
  const _OverviewMetric(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      CountUpAnimation(
        value: value.toDouble(),
        style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color),
      ),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    ]);
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
