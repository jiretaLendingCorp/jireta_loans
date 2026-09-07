// lib/presentation/features/lender/loans/screens/lender_loan_application_status_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/route_constants.dart';
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
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Transaction',
      route: RouteConstants.lenderPaymentHistory),

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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
    final ciStatus = loan.ciStatus as String? ?? '';
    final disbursementMethod = loan.disbursementMethod as String?;
    final disbursedAt = loan.disbursedAt;
    // ciStatus: assigned/accepted/in_progress/completed(pending approval)/approved/rejected
    final isRejected = status == 'rejected';
    final isActive = status == 'active' || status == 'completed';
    final loanApproved = ['approved', 'active', 'completed'].contains(status);
    final ciDone = ['in_progress', 'completed', 'approved'].contains(ciStatus) ||
        ['ci_completed', 'approved', 'active', 'completed', 'rejected']
            .contains(status);
    final awaitingRelease = loanApproved &&
        !isActive &&
        disbursedAt == null &&
        disbursementMethod != null &&
        disbursementMethod.isNotEmpty;
    final needsMethodChoice = loanApproved &&
        !isActive &&
        disbursedAt == null &&
        (disbursementMethod == null || disbursementMethod.isEmpty);

    String methodLabel(String? m) {
      switch (m) {
        case 'rider_delivery':
          return 'Cash on Delivery';
        case 'office_cash':
          return 'Pick Up at Office';
        case 'gcash':
          return 'GCash';
        default:
          return 'your chosen method';
      }
    }

    final steps = <_Step>[
      const _Step('Applied', 'Loan application submitted successfully.', true,
          Icons.description),
      _Step(
          'Under Review',
          'Staff is reviewing your application.',
          ['under_review', 'ci_required', 'ci_assigned', 'ci_completed', 'approved', 'active', 'completed', 'rejected']
              .contains(status),
          Icons.manage_search),
      _Step(
          'Credit Investigation — Rider Assigned',
          ciStatus == 'assigned'
              ? 'Rider assigned and will visit your address.'
              : 'A field officer will visit your address for verification.',
          ['ci_assigned', 'ci_completed', 'approved', 'active', 'completed', 'rejected']
              .contains(status),
          Icons.pin_drop),
      _Step('CI In Progress', 'Rider is conducting field investigation.', ciDone,
          Icons.timelapse),
      if (isRejected)
        const _Step('Rejected', 'Your application has been rejected.', true,
            Icons.cancel, isError: true)
      else
        _Step(
          'Approved',
          needsMethodChoice
              ? 'Loan approved! Please choose your disbursement method to receive funds.'
              : awaitingRelease
                  ? 'Loan approved! Funds are being prepared for ${methodLabel(disbursementMethod)} release.'
                  : isActive
                      ? 'Loan approved! Your funds have been released.'
                      : 'Awaiting CI and loan approval.',
          loanApproved,
          Icons.check_circle,
        ),
      if (!isRejected && isActive)
        const _Step(
            'Funds Released',
            'Funds have been released. Your loan is now active.',
            true,
            Icons.payments),
      if (awaitingRelease)
        _Step(
          'Awaiting Release',
          disbursementMethod == 'rider_delivery'
              ? 'A rider will deliver the cash to your registered address. You will be notified once the delivery is on its way.'
              : disbursementMethod == 'office_cash'
                  ? 'Your cash is being prepared at the Jireta Loans office. You will be notified when it is ready for pickup.'
                  : 'Your disbursement is being processed. You will be notified once the funds are released.',
          false,
          Icons.hourglass_top_rounded,
        ),
      if (!isRejected && needsMethodChoice)
        const _Step(
            'Choose Disbursement Method',
            'Select how you want to receive your funds to continue.',
            false,
            Icons.account_balance_wallet_outlined),
    ];

    return Column(
        children: steps.asMap().entries
            .map((e) => _TimelineTile(step: e.value, isLast: e.key == steps.length - 1))
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

