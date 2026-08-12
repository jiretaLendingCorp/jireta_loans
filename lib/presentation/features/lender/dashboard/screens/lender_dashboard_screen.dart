// lib/presentation/features/lender/dashboard/screens/lender_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/animated/count_up_animation.dart';
import '../../loans/providers/lender_loan_provider.dart';
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

  LoanModel? _approvedUnreleased(List<LoanModel> loans) {
    for (final loan in loans) {
      if (loan.status == 'approved' && loan.disbursedAt == null) {
        return loan;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderDashboardProvider);
    final loanState = ref.watch(lenderLoanProvider);
    final activeLoan = loanState.isLoading ? null : loanState.activeLoan;
    final approvedLoan = _approvedUnreleased(loanState.loans);

    return MobileScaffold(
      title: 'My Account',
      accentColor: AppColors.lenderPurple,
      navItems: _riderNavItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : RefreshIndicator(
              onRefresh: () async {
                await ref.read(lenderDashboardProvider.notifier).load();
                await ref.read(lenderLoanProvider.notifier).loadLoans();
              },
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
                      if (approvedLoan != null) ...[
                        _ApprovedLoanBanner(loan: approvedLoan),
                        const SizedBox(height: 20),
                      ],
                      if (activeLoan == null) ...[
                        _QuickActions(context: context),
                        const SizedBox(height: 20),
                      ],
                      if (activeLoan != null) ...[
                        _MyLoanCard(loan: activeLoan),
                        const SizedBox(height: 24),
                        _LoanHistorySection(
                          loans: loanState.loans,
                          activeLoanId: activeLoan.id,
                        ),
                      ] else
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
            decimalPlaces: 2,
          ),
        ],
      ),
    );
  }
}

class _ApprovedLoanBanner extends StatelessWidget {
  final LoanModel loan;
  const _ApprovedLoanBanner({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(RouteConstants.lenderLoans),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.lenderPurple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.lenderPurple.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppColors.lenderPurple,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loan #${loan.loanNumber} Approved',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Choose how you want to receive your funds to complete the release.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.lenderPurple),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final BuildContext context;
  const _QuickActions({required this.context});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: _ActionBtn(
        icon: Icons.add_circle_outline,
        label: 'Apply Loan',
        color: AppColors.lenderPurple,
        onTap: () => context.push(RouteConstants.lenderLoans),
      ),
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

class _MyLoanCard extends StatelessWidget {
  final LoanModel loan;
  const _MyLoanCard({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('My Loan'),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => context.push(
            RouteConstants.lenderLoanDetails.replaceFirst(':id', loan.id),
          ),
          child: Container(
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        loan.status == 'overdue'
                            ? 'Overdue Loan'
                            : 'Active Loan',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    StatusBadge(status: loan.status, small: true),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Outstanding Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                CountUpAnimation(
                  value: loan.outstandingBalance,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'PlayfairDisplay',
                  ),
                  prefix: '₱',
                  decimalPlaces: 2,
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Payable',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      loan.totalPayable.toCurrency,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoanHistorySection extends StatelessWidget {
  final List<LoanModel> loans;
  final String activeLoanId;

  const _LoanHistorySection({
    required this.loans,
    required this.activeLoanId,
  });

  @override
  Widget build(BuildContext context) {
    final pastLoans =
        loans.where((l) => l.id != activeLoanId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _SectionLabel('Loan History'),
            GestureDetector(
              onTap: () => context.push(RouteConstants.lenderLoanHistory),
              child: const Row(
                children: [
                  Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.lenderPurple,
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 16, color: AppColors.lenderPurple),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (pastLoans.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.history_outlined,
                    color: AppColors.textTertiary, size: 20),
                SizedBox(width: 10),
                Text(
                  'No past loans yet',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ...pastLoans.take(3).map(
                (loan) => _LoanHistoryTile(
                  loan: loan,
                  onTap: () => context.push(
                    RouteConstants.lenderLoanDetails.replaceFirst(
                        ':id', loan.id),
                  ),
                ),
              ),
      ],
    );
  }
}

class _LoanHistoryTile extends StatelessWidget {
  final LoanModel loan;
  final VoidCallback onTap;

  const _LoanHistoryTile({required this.loan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      loan.loanNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    StatusBadge(status: loan.status, small: true),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Principal',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                        Text(
                          loan.principalAmount.toCurrency,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Total Payable',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                        Text(
                          loan.totalPayable.toCurrency,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.lenderPurple),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Applied: ${loan.createdAt.toDateString()}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ),
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
