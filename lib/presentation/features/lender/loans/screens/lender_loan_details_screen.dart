// lib/presentation/features/lender/loans/screens/lender_loan_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
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

class LenderLoanDetailsScreen extends ConsumerStatefulWidget {
  final String loanId;
  const LenderLoanDetailsScreen({super.key, required this.loanId});

  @override
  ConsumerState<LenderLoanDetailsScreen> createState() =>
      _LenderLoanDetailsScreenState();
}

class _LenderLoanDetailsScreenState
    extends ConsumerState<LenderLoanDetailsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(lenderLoanProvider.notifier).loadLoanDetails(widget.loanId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderLoanProvider);
    final loan = state.selectedLoan;

    return MobileScaffold(
      title: 'Loan Details',
      accentColor: AppColors.lenderPurple,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: state.isLoading
          ? const ShimmerLoader()
          : loan == null
              ? const Center(
                  child: Text('Loan not found',
                      style: TextStyle(color: AppColors.textSecondary)))
              : RefreshIndicator(
                  color: AppColors.lenderPurple,
                  onRefresh: () => ref
                      .read(lenderLoanProvider.notifier)
                      .loadLoanDetails(widget.loanId),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LoanHeader(loan: loan),
                        const SizedBox(height: 16),
                        _AmountCard(loan: loan),
                        const SizedBox(height: 16),
                        _InfoCard(loan: loan),
                        const SizedBox(height: 16),
                        if (loan.status == 'active') ...[
                          AppButton(
                            label: 'Pay via GCash',
                            onPressed: () => context.push(
                                RouteConstants.lenderPayViaGcash,
                                extra: {'loan_id': loan.id}),
                            color: AppColors.lenderPurple,
                            icon: Icons.payment,
                          ),
                          const SizedBox(height: 10),
                          AppButton(
                            label: 'View Payment Schedule',
                            onPressed: () =>
                                context.push(RouteConstants.lenderPayments),
                            color: AppColors.info,
                            icon: Icons.calendar_month,
                            outlined: true,
                          ),
                        ],
                        if (loan.status == 'pending' ||
                            loan.status == 'under_review') ...[
                          AppButton(
                            label: 'Cancel Application',
                            onPressed: () => _confirmCancel(context),
                            color: AppColors.error,
                            outlined: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Application'),
        content: const Text(
            'Are you sure you want to cancel this loan application?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Yes', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(lenderLoanProvider.notifier).cancelLoan(widget.loanId);
      if (!context.mounted) return;
      context.pop();
    }
  }
}

class _LoanHeader extends StatelessWidget {
  final dynamic loan;
  const _LoanHeader({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.lenderPurple, AppColors.lenderPurpleLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(loan.loanNumber ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  (loan.status ?? '').replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Outstanding Balance',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          Text(
            (loan.outstandingBalance as num?)?.toCurrency ?? '₱0.00',
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
              'Applied: ${loan.createdAt != null ? (loan.createdAt as DateTime).toDateString() : ''}',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  final dynamic loan;
  const _AmountCard({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Loan Summary',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          _row('Principal Amount',
              (loan.principalAmount as num?)?.toCurrency ?? '₱0.00'),
          _divider(),
          _row('Interest (20%)',
              (loan.interestAmount as num?)?.toCurrency ?? '₱0.00'),
          _divider(),
          _row('Total Payable',
              (loan.totalPayable as num?)?.toCurrency ?? '₱0.00',
              bold: true),
          _divider(),
          _row('Installment',
              (loan.installmentAmount as num?)?.toCurrency ?? '₱0.00'),
          _divider(),
          _row('Frequency', (loan.paymentFrequency ?? '').toUpperCase()),
          _divider(),
          _row('Term', '${loan.termDays ?? 0} days'),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.textPrimary)),
          ],
        ),
      );

  Widget _divider() => const Divider(height: 1, color: AppColors.divider);
}

class _InfoCard extends StatelessWidget {
  final dynamic loan;
  const _InfoCard({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Disbursement Info',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          _row(
              'Method',
              (loan.disbursementMethod ?? 'N/A')
                  .replaceAll('_', ' ')
                  .toUpperCase()),
          const Divider(height: 1, color: AppColors.divider),
          _row(
              'Disbursed At',
              loan.disbursedAt != null
                  ? (loan.disbursedAt as DateTime).toDateString()
                  : 'Not yet disbursed'),
          const Divider(height: 1, color: AppColors.divider),
          _row('Purpose', loan.purpose ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            Flexible(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                    textAlign: TextAlign.end)),
          ],
        ),
      );
}
