// lib/presentation/features/lender/loans/screens/lender_loan_history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/lender_loan_provider.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
  MobileNavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'History',
      route: RouteConstants.lenderPaymentHistory),
  MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile),
];

class LenderLoanHistoryScreen extends ConsumerStatefulWidget {
  const LenderLoanHistoryScreen({super.key});

  @override
  ConsumerState<LenderLoanHistoryScreen> createState() => _State();
}

class _State extends ConsumerState<LenderLoanHistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(lenderLoanProvider.notifier).loadLoans());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderLoanProvider);

    return MobileScaffold(
      title: 'Recent Transactions',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: state.isLoading
          ? ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: 5,
              itemBuilder: (_, __) => const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: ShimmerLoader(height: 90, borderRadius: 12)),
            )
          : state.loans.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 64,
                          color: AppColors.textTertiary.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text('No transactions yet',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 15)),
                      const SizedBox(height: 6),
                      const Text('Your loan transactions will appear here',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 12)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.lenderBlue,
                  onRefresh: () =>
                      ref.read(lenderLoanProvider.notifier).loadLoans(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: state.loans.length,
                    itemBuilder: (_, i) => _LoanCard(
                        key: ValueKey(state.loans[i].id),
                        loan: state.loans[i],
                        onTap: () =>
                            context.push('/lender/loans/${state.loans[i].id}')),
                  ),
                ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  final dynamic loan;
  final VoidCallback onTap;
  const _LoanCard({super.key, required this.loan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = (loan.status ?? '').toString().toLowerCase();
    final isActive = status == 'active';
    final isApproved = status == 'approved';
    final isRejected = status == 'rejected';
    final isPending = ['pending', 'under_review', 'ci_required', 'ci_assigned', 'ci_completed'].contains(status);

    final Color accent;
    final IconData icon;
    final String txnLabel;
    if (isActive) {
      accent = AppColors.lenderBlue;
      icon = Icons.account_balance_wallet_rounded;
      txnLabel = 'Active Loan';
    } else if (isApproved) {
      accent = AppColors.success;
      icon = Icons.check_circle_rounded;
      txnLabel = 'Approved';
    } else if (isRejected) {
      accent = AppColors.error;
      icon = Icons.cancel_rounded;
      txnLabel = 'Rejected';
    } else if (isPending) {
      accent = AppColors.warning;
      icon = Icons.hourglass_top_rounded;
      txnLabel = 'Pending';
    } else {
      accent = AppColors.textTertiary;
      icon = Icons.receipt_long_rounded;
      txnLabel = (loan.status ?? '').toString().replaceAll('_', ' ').toUpperCase();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: accent.withValues(alpha: 0.15)),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loan.loanNumber ?? 'Loan',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(txnLabel,
                        style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      loan.createdAt != null ? (loan.createdAt as DateTime).toDateString() : '',
                      style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text((loan.principalAmount as num?)?.toCurrency ?? '₱0',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text((loan.paymentFrequency ?? '').toString().toUpperCase(),
                      style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                    StatusBadge(status: loan.status ?? ''),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
