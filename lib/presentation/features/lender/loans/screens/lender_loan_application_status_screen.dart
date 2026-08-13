// lib/presentation/features/lender/loans/screens/lender_loan_application_status_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
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

class LenderLoanApplicationStatusScreen extends ConsumerStatefulWidget {
  final String loanId;
  const LenderLoanApplicationStatusScreen({super.key, required this.loanId});

  @override
  ConsumerState<LenderLoanApplicationStatusScreen> createState() => _State();
}

class _State extends ConsumerState<LenderLoanApplicationStatusScreen> {
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
      title: 'Application Status',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: state.isLoading
          ? const ShimmerLoader()
          : loan == null
              ? const Center(child: Text('Loan not found'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LoanSummaryCard(loan: loan),
                      const SizedBox(height: 20),
                      const Text('Application Timeline',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 14),
                      _buildTimeline(loan),
                      if (loan.status == 'rejected' &&
                          loan.rejectionReason != null) ...[
                        const SizedBox(height: 16),
                        _RejectionCard(reason: loan.rejectionReason!),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildTimeline(dynamic loan) {
    final status = loan.status as String? ?? '';
    final steps = [
      const _Step('Applied', 'Loan application submitted successfully.', true,
          Icons.description),
      _Step(
          'Under Review',
          'Staff is reviewing your application.',
          [
            'under_review',
            'ci_required',
            'ci_assigned',
            'ci_completed',
            'approved',
            'active',
            'completed',
            'rejected'
          ].contains(status),
          Icons.manage_search),
      _Step(
          'Credit Investigation',
          'A field officer will visit your address.',
          ['ci_assigned', 'ci_completed', 'approved', 'active', 'completed']
              .contains(status),
          Icons.pin_drop),
      _Step(
          'CI Completed',
          'Credit investigation report submitted.',
          ['ci_completed', 'approved', 'active', 'completed'].contains(status),
          Icons.task_alt),
      _Step(
        status == 'rejected' ? 'Rejected' : 'Approved',
        status == 'rejected'
            ? 'Your application has been rejected.'
            : 'Application approved! Awaiting fund release.',
        ['approved', 'active', 'completed', 'rejected'].contains(status),
        status == 'rejected' ? Icons.cancel : Icons.check_circle,
        isError: status == 'rejected',
      ),
    ];

    return Column(
        children: steps
            .asMap()
            .entries
            .map((e) =>
                _TimelineTile(step: e.value, isLast: e.key == steps.length - 1))
            .toList());
  }
}

class _Step {
  final String title, subtitle;
  final bool done;
  final IconData icon;
  final bool isError;
  const _Step(this.title, this.subtitle, this.done, this.icon,
      {this.isError = false});
}

class _TimelineTile extends StatelessWidget {
  final _Step step;
  final bool isLast;
  const _TimelineTile({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = step.isError
        ? AppColors.error
        : step.done
            ? AppColors.success
            : AppColors.border;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: step.done
                    ? color.withValues(alpha: 0.1)
                    : AppColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(
                    color: step.done ? color : AppColors.border, width: 2),
              ),
              child: Icon(step.icon,
                  size: 18, color: step.done ? color : AppColors.textTertiary),
            ),
            if (!isLast)
              Container(
                  width: 2,
                  height: 44,
                  color: step.done
                      ? color.withValues(alpha: 0.3)
                      : AppColors.border),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: step.done
                            ? AppColors.textPrimary
                            : AppColors.textTertiary)),
                const SizedBox(height: 4),
                Text(step.subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoanSummaryCard extends StatelessWidget {
  final dynamic loan;
  const _LoanSummaryCard({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3))
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
                      color: AppColors.textSecondary, fontSize: 12)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.lenderBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                    (loan.status ?? '').replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.lenderBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _InfoCol(
                  'Amount', (loan.principalAmount as num?)?.toCurrency ?? '₱0'),
              _InfoCol('Total Payable',
                  (loan.totalPayable as num?)?.toCurrency ?? '₱0'),
              _InfoCol(
                  'Frequency', (loan.paymentFrequency ?? '').toUpperCase()),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCol extends StatelessWidget {
  final String label, value;
  const _InfoCol(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ],
      );
}

class _RejectionCard extends StatelessWidget {
  final String reason;
  const _RejectionCard({required this.reason});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.errorLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text('Rejection Reason: $reason',
                    style:
                        const TextStyle(fontSize: 13, color: AppColors.error))),
          ],
        ),
      );
}
