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
                      if (loan.status == 'approved' && loan.disbursedAt == null) ...[
                        const SizedBox(height: 20),
                        _DisbursementChoiceCard(loan: loan),
                      ],
                      // NOTE: Lender does NOT show the "awaiting manager approval" solid box — that design is staff-only.
                      // Timeline step _Step('CI Submitted — Awaiting Manager Approval' with isWarning) already informs lender.
                      // Removed the extra Container to satisfy spec: no approval-like design in lender role after rider CI.
                    ],
                  ),
                ),
    );
  }

  Widget _buildTimeline(dynamic loan) {
    final status = loan.status as String? ?? '';
    final ciStatus = loan.ciStatus as String? ?? '';
    // ciStatus: assigned/accepted/in_progress/completed(pending approval)/approved/rejected
    final ciSubmitted = ['completed', 'approved', 'rejected'].contains(ciStatus) || ['ci_completed', 'approved', 'active', 'completed'].contains(status);
    final loanApproved = ['approved', 'active', 'completed'].contains(status);
    final steps = [
      const _Step('Applied', 'Loan application submitted successfully.', true, Icons.description),
      _Step('Under Review', 'Staff is reviewing your application.', ['under_review', 'ci_required', 'ci_assigned', 'ci_completed', 'approved', 'active', 'completed', 'rejected'].contains(status), Icons.manage_search),
      _Step('Credit Investigation — Rider Assigned', ciStatus == 'assigned' ? 'Rider assigned and will visit your address.' : 'A field officer will visit your address for verification.', ['ci_assigned', 'ci_completed', 'approved', 'active', 'completed'].contains(status), Icons.pin_drop),
      _Step('CI In Progress', 'Rider is conducting field investigation.', ['in_progress', 'completed', 'approved'].contains(ciStatus) || ciSubmitted, Icons.timelapse),
      _Step(
        status == 'rejected' ? 'Rejected' : status == 'active' ? 'Funds Released' : 'Approved',
        status == 'rejected' ? 'Your application has been rejected.' : status == 'active' ? 'Funds have been released. Your loan is now active.' : loanApproved ? 'Loan approved! Please choose disbursement method to receive funds.' : 'Awaiting CI and loan approval.',
        status == 'rejected' || status == 'active' || status == 'completed',
        status == 'rejected' ? Icons.cancel : status == 'active' ? Icons.payments : Icons.check_circle,
        isError: status == 'rejected',
      ),
    ];

    return Column(children: steps.asMap().entries.map((e) => _TimelineTile(step: e.value, isLast: e.key == steps.length - 1)).toList());
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

class _DisbursementChoiceCard extends ConsumerWidget {
  final dynamic loan;
  const _DisbursementChoiceCard({required this.loan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.deepNavy, Color(0xFF1A3658)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.lenderBlue.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.celebration_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Loan Approved — Choose Disbursement', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
          const SizedBox(height: 8),
          const Text('Your loan has been approved after CI review! Now choose how you want to receive your funds:', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
          const SizedBox(height: 14),
          _ChoiceButton(
            icon: Icons.storefront_rounded,
            label: 'Pick Up at Office',
            subtitle: 'Visit our office to claim cash',
            onTap: () async {
              final ok = await ref.read(lenderLoanProvider.notifier).selectDisbursementMethod(loanId: loan.id, method: 'office_cash');
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Office pickup selected. We will notify you when funds are ready.'), backgroundColor: AppColors.success));
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${ref.read(lenderLoanProvider).error ?? 'try again'}'), backgroundColor: AppColors.error));
              }
            },
          ),
          const SizedBox(height: 10),
          _ChoiceButton(
            icon: Icons.delivery_dining_rounded,
            label: 'Cash via Rider',
            subtitle: 'Rider will deliver cash to your address',
            onTap: () async {
              final ok = await ref.read(lenderLoanProvider.notifier).selectDisbursementMethod(loanId: loan.id, method: 'rider_delivery');
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rider delivery selected. A rider will be scheduled to deliver your funds.'), backgroundColor: AppColors.success));
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${ref.read(lenderLoanProvider).error ?? 'try again'}'), backgroundColor: AppColors.error));
              }
            },
          ),
          const SizedBox(height: 8),
          const Text('GCash disbursement is coming soon. Please choose Office or Rider for now.', style: TextStyle(color: Colors.white60, fontSize: 10)),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _ChoiceButton({required this.icon, required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withValues(alpha: 0.6))),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.lenderBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: AppColors.lenderBlue, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ])),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ]),
        ),
      ),
    );
  }
}
