// lib/presentation/features/lender/payments/screens/lender_payment_schedule_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../../data/models/loan_schedule_model.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/lender_payment_provider.dart';
import '../../collections/providers/lender_collection_provider.dart';
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
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    await ref.read(lenderLoanProvider.notifier).loadLoans();
    if (!mounted) return;
    final loan = _pickLoan(ref.read(lenderLoanProvider));
    if (loan != null) {
      await ref.read(lenderLoanProvider.notifier).loadLoanDetails(loan.id);
    }
    if (!mounted) return;
    setState(() => _resolving = false);
    ref.read(lenderPaymentProvider.notifier).loadPayments();
  }

  /// The lender's relevant loan for the schedule: the active one, or the
  /// approved loan that is awaiting fund release.
  LoanModel? _pickLoan(LenderLoanState state) {
    if (state.activeLoan != null) return state.activeLoan;
    for (final l in state.loans) {
      if (l.status == 'approved') return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loanState = ref.watch(lenderLoanProvider);
    final loan = loanState.selectedLoan;
    final schedules = (loan?.schedules ?? const [])
        .map((e) => LoanScheduleModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final collAsync = ref.watch(lenderCollectionProvider);
    final collItems = collAsync.valueOrNull?['items'] as List? ?? [];
    final collectionBySchedule = <String, String>{};
    final collectionTypeBySchedule = <String, String>{};
    for (final item in collItems) {
      if (item is! Map) continue;
      final schedId = item['loan_schedule_id'] as String? ?? '';
      final status = item['status'] as String? ?? '';
      if (schedId.isNotEmpty &&
          ['requested', 'assigned', 'accepted', 'in_progress']
              .contains(status)) {
        collectionBySchedule[schedId] = status;
        collectionTypeBySchedule[schedId] =
            (item['collection_type'] as String? ?? 'rider');
      }
    }

    return MobileScaffold(
      title: 'Payment Schedule',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      appBarActions: [
        IconButton(
          icon: const Icon(Icons.history, color: Colors.white),
          tooltip: 'Payment History',
          onPressed: () => context.push(RouteConstants.lenderPaymentHistory),
        ),
      ],
      body: _resolving || loanState.isLoading
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
                            color:
                                AppColors.textTertiary.withValues(alpha: 0.5)),
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
                                collectionStatus: collectionBySchedule[
                                    schedules[i].id],
                                collectionType: collectionTypeBySchedule[
                                    schedules[i].id],
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
      color: AppColors.lenderBlue,
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
  final LoanScheduleModel schedule;
  final int index;
  final String activeLoanId;
  final String? collectionStatus;
  final String? collectionType;
  const _ScheduleTile(
      {required this.schedule,
      required this.index,
      required this.activeLoanId,
      this.collectionStatus,
      this.collectionType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaid = schedule.status == 'paid';
    final isOverdue = schedule.status == 'overdue';
    // Payable in any state that still has an unpaid remainder: pending,
    // partially paid (top-up), overdue, or a future installment (advance
    // payment). Only fully-paid installments are excluded.
    final canPay = !isPaid && collectionStatus == null;

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
                      : AppColors.lenderBlue.withValues(alpha: 0.08),
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
                              : AppColors.lenderBlue)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Due: ${schedule.dueDate.toDateString()}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(
                    'Amount: ${schedule.amountDue.toCurrency}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(status: schedule.status),
              const SizedBox(height: 6),
              if (collectionStatus != null)
                _CollectionChip(
                    status: collectionStatus!,
                    type: collectionType ?? 'rider')
              else if (canPay)
                GestureDetector(
                  onTap: () =>
                      context.push(RouteConstants.lenderPaymentMethod, extra: {
                    'loan_id': activeLoanId,
                    'schedule_id': schedule.id,
                    'amount': schedule.remainingAmount > 0
                        ? schedule.remainingAmount
                        : schedule.amountDue,
                    'due_date': schedule.dueDate.toDateString(),
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.lenderBlue,
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

class _CollectionChip extends StatelessWidget {
  final String status;
  final String type;
  const _CollectionChip({required this.status, this.type = 'rider'});

  @override
  Widget build(BuildContext context) {
    final isPendingRequest = status == 'requested';
    final isOffice = type == 'office';
    final label = isPendingRequest
        ? (isOffice
            ? 'Office visit pending'
            : 'Rider collection pending')
        : (isOffice
            ? 'Office visit in progress'
            : 'Rider collection in progress');
    final color =
        isPendingRequest ? AppColors.warning : AppColors.lenderBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              isOffice
                  ? Icons.storefront_outlined
                  : Icons.delivery_dining_outlined,
              size: 13,
              color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
