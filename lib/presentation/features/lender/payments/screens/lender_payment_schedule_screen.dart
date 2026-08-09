// lib/presentation/features/lender/payments/screens/lender_payment_schedule_screen.dart
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
import '../providers/lender_payment_provider.dart';
import '../../loans/providers/lender_loan_provider.dart';

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

class LenderPaymentScheduleScreen extends ConsumerStatefulWidget {
  const LenderPaymentScheduleScreen({super.key});

  @override
  ConsumerState<LenderPaymentScheduleScreen> createState() => _State();
}

class _State extends ConsumerState<LenderPaymentScheduleScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(lenderLoanProvider.notifier).loadLoans();
      ref.read(lenderPaymentProvider.notifier).loadPayments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loanState = ref.watch(lenderLoanProvider);
    final loan = loanState.activeLoan;
    final schedules = loan?.schedules ?? [];

    return MobileScaffold(
      title: 'Payment Schedule',
      accentColor: AppColors.lenderPurple,
      navItems: _lenderNavItems,
      appBarActions: [
        IconButton(
          icon: const Icon(Icons.history, color: Colors.white),
          tooltip: 'Payment History',
          onPressed: () => context.push(RouteConstants.lenderPaymentHistory),
        ),
      ],
      body: loanState.isLoading
          ? const ShimmerLoader()
          : loan == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_outlined,
                            size: 64,
                            color: AppColors.textTertiary.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        const Text('No active loan found',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 15)),
                        const SizedBox(height: 8),
                        const Text(
                          'You can apply for a loan from the My Loan tab once your account is verified.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    _LoanSummaryHeader(loan: loan),
                    Expanded(
                      child: schedules.isEmpty
                          ? const Center(child: Text('No schedule available'))
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: schedules.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _ScheduleTile(
                                schedule: schedules[i],
                                index: i,
                                activeLoanId: loan.id,
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _LoanSummaryHeader extends StatelessWidget {
  final dynamic loan;
  const _LoanSummaryHeader({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      color: AppColors.lenderPurple,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Col('Outstanding',
                  (loan.outstandingBalance as num?)?.toCurrency ?? '₱0'),
              _Col('Total Payable',
                  (loan.totalPayable as num?)?.toCurrency ?? '₱0'),
              _Col('Frequency', (loan.paymentFrequency ?? '').toUpperCase()),
            ],
          ),
        ],
      ),
    );
  }
}

class _Col extends StatelessWidget {
  final String label, value;
  const _Col(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.white70)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      );
}

class _ScheduleTile extends ConsumerWidget {
  final dynamic schedule;
  final int index;
  final String activeLoanId;
  const _ScheduleTile(
      {required this.schedule,
      required this.index,
      required this.activeLoanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaid = schedule.status == 'paid';
    final isOverdue = schedule.status == 'overdue';
    final isPending = schedule.status == 'pending';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPaid
              ? AppColors.success.withValues(alpha: 0.3)
              : isOverdue
                  ? AppColors.error.withValues(alpha: 0.3)
                  : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isPaid
                  ? AppColors.success.withValues(alpha: 0.1)
                  : isOverdue
                      ? AppColors.error.withValues(alpha: 0.1)
                      : AppColors.lenderPurple.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isPaid
                          ? AppColors.success
                          : isOverdue
                              ? AppColors.error
                              : AppColors.lenderPurple)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Due: ${schedule.dueDate != null ? (schedule.dueDate as DateTime).toDateString() : ''}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(
                    'Amount: ${(schedule.amountDue as num?)?.toCurrency ?? '₱0'}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(status: schedule.status ?? 'pending'),
              const SizedBox(height: 6),
              if (isPending)
                GestureDetector(
                  onTap: () => context.push(RouteConstants.lenderPayViaGcash,
                      extra: {
                        'loan_id': activeLoanId,
                        'schedule_id': schedule.id
                      }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.lenderPurple,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Pay',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
