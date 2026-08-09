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
      icon: Icons.payment_outlined,
      activeIcon: Icons.payment,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
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
      title: 'Loan History',
      accentColor: AppColors.lenderPurple,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: state.isLoading
          ? ListView.builder(
              padding: const EdgeInsets.all(16),
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
                      Icon(Icons.history_outlined,
                          size: 64,
                          color: AppColors.textTertiary.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text('No loan history yet',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 15)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.lenderPurple,
                  onRefresh: () =>
                      ref.read(lenderLoanProvider.notifier).loadLoans(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.loans.length,
                    itemBuilder: (_, i) => _LoanCard(
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
  const _LoanCard({required this.loan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(loan.loanNumber ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary)),
                StatusBadge(status: loan.status ?? ''),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _InfoItem('Principal',
                    (loan.principalAmount as num?)?.toCurrency ?? '₱0'),
                _InfoItem('Total Payable',
                    (loan.totalPayable as num?)?.toCurrency ?? '₱0'),
                _InfoItem(
                    'Frequency', (loan.paymentFrequency ?? '').toUpperCase()),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              loan.createdAt != null
                  ? 'Applied: ${(loan.createdAt as DateTime).toDateString()}'
                  : '',
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label, value;
  const _InfoItem(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ],
      );
}
