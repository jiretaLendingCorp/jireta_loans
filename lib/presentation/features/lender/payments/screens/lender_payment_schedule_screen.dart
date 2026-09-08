// lib/presentation/features/lender/payments/screens/lender_payment_schedule_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../../data/models/loan_schedule_model.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
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

  /// The lender's relevant loan for the schedule. ONLY a disbursed loan
  /// (active/overdue) has a payment schedule — an approved-but-not-yet-
  /// released loan must still show "No active loan found" until the funds
  /// are actually handed out.
  LoanModel? _pickLoan(LenderLoanState state) => state.activeLoan;

  @override
  Widget build(BuildContext context) {
    final loanState = ref.watch(lenderLoanProvider);
    // ONLY a disbursed (active/overdue) loan may show a schedule. Never fall
    // back to a stale selectedLoan from an approved/not-yet-released loan.
    final hasActiveLoan = loanState.activeLoan != null;
    final loan =
        hasActiveLoan ? (loanState.selectedLoan ?? loanState.activeLoan) : null;
    final schedules = (loan?.schedules ?? const [])
        .map((e) => LoanScheduleModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final collAsync = ref.watch(lenderCollectionProvider);
    final raw = collAsync.valueOrNull;
    // Provider now normalizes to both 'items' and 'data', but be defensive
    // against old cached shapes or direct server shape.
    final collItems =
        (raw?['items'] as List?) ?? (raw?['data'] as List?) ?? const [];
    final collectionBySchedule = <String, String>{};
    final collectionTypeBySchedule = <String, String>{};
    for (final item in collItems) {
      if (item is! Map) continue;
      // Prefer the flat foreign key added to COLLECTION_SELECT; fall back to
      // the embedded loan_schedule.id for rows from older deployments.
      final schedId = (item['loan_schedule_id'] as String?) ??
          (item['loan_schedule'] is Map
              ? (item['loan_schedule'] as Map)['id'] as String?
              : null) ??
          '';
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
          ? const _PaymentScheduleSkeleton()
          : loan == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Premium circular badge
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.lenderBlue,
                              AppColors.lenderBlueLight
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.lenderBlue.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No Active Loan Yet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 36),
                        child: Text(
                          'Your payment schedule will appear here once your loan is released and active.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Material(
                        color: AppColors.lenderBlue,
                        borderRadius: BorderRadius.circular(99),
                        child: InkWell(
                          onTap: () => context.push(RouteConstants.lenderLoans),
                          borderRadius: BorderRadius.circular(99),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 22, vertical: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded,
                                    color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Apply for a Loan',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _LoanSummaryHeader(loan: loan),
                    Expanded(
                      child: schedules.isEmpty
                          ? _NoScheduleState(
                              onRetry: _load,
                              onContactUs: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Your schedule will appear as soon as your loan is released. If this loan is already active, pull down or tap Retry to reload.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 100),
                                itemCount: schedules.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) => _ScheduleTile(
                                  schedule: schedules[i],
                                  index: i,
                                  activeLoanId: loan.id,
                                  loanStatus: loan.status,
                                  collectionStatus:
                                      collectionBySchedule[schedules[i].id],
                                  collectionType:
                                      collectionTypeBySchedule[schedules[i].id],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _NoScheduleState extends StatelessWidget {
  final Future<void> Function() onRetry;
  final VoidCallback onContactUs;
  const _NoScheduleState({required this.onRetry, required this.onContactUs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.lenderBlueLight,
              ),
              child: const Icon(Icons.event_note_outlined,
                  color: AppColors.lenderBlue, size: 34),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Schedule Available Yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your repayment schedule is generated when your loan is released. '
              'If your loan is already active and this still shows empty, tap '
              'Retry to reload the latest schedule.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Material(
              color: AppColors.lenderBlue,
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                onTap: onRetry,
                borderRadius: BorderRadius.circular(99),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
  final String? loanStatus;
  final String? collectionStatus;
  final String? collectionType;
  const _ScheduleTile(
      {required this.schedule,
      required this.index,
      required this.activeLoanId,
      this.loanStatus,
      this.collectionStatus,
      this.collectionType});

  void _showPendingDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Already Pending'),
        content: const Text('You have already pending payment'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showLoanNotReadyDialog(BuildContext context) {
    final status = loanStatus ?? 'unknown';
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Loan Not Ready'),
        content: Text(
          'Your loan status is "$status". Only Active or Overdue loans can be collected. '
          'If your loan was just approved, please wait for fund release/disbursement. '
          'Contact the office if you think this is an error.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaid = schedule.status == 'paid';
    final isOverdue = schedule.status == 'overdue';
    final isLoanPayable = loanStatus == 'active' || loanStatus == 'overdue';
    // Payable in any state that still has an unpaid remainder: pending,
    // partially paid (top-up), overdue, or a future installment (advance
    // payment). Only fully-paid installments are excluded.
    // Additionally the parent LOAN must be active/overdue — approved/under_review
    // loans are not yet disbursed so the backend correctly rejects with
    // "Loan is not in a payable status". We surface that upfront.
    final canPay = !isPaid && collectionStatus == null && isLoanPayable;
    final canPayButLoanNotReady =
        !isPaid && collectionStatus == null && !isLoanPayable;

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
                Text('Due: ${schedule.dueDate.toDateString()}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text('Amount: ${schedule.amountDue.toCurrency}',
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
                GestureDetector(
                  onTap: () => _showPendingDialog(context),
                  child: _CollectionChip(
                      status: collectionStatus!,
                      type: collectionType ?? 'rider'),
                )
              else if (canPayButLoanNotReady)
                GestureDetector(
                  onTap: () => _showLoanNotReadyDialog(context),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Pay',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                )
              else if (canPay)
                GestureDetector(
                  onTap: () {
                    // Defensive: if the collection list just finished loading
                    // and this tile flipped to pending between build and tap,
                    // show the pending dialog instead of navigating.
                    if (collectionStatus != null) {
                      _showPendingDialog(context);
                      return;
                    }
                    // Loan must be active/overdue per backend handleCollectionRequest.
                    // Approved/under_review loans are not yet disbursed and will
                    // be rejected with "Loan is not in a payable status".
                    if (!isLoanPayable) {
                      _showLoanNotReadyDialog(context);
                      return;
                    }
                    context.push(RouteConstants.lenderPaymentMethod, extra: {
                      'loan_id': activeLoanId,
                      'schedule_id': schedule.id,
                      'amount': schedule.remainingAmount > 0
                          ? schedule.remainingAmount
                          : schedule.amountDue,
                      'due_date': schedule.dueDate.toDateString(),
                    });
                  },
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
        ? (isOffice ? 'Office visit pending' : 'Rider collection pending')
        : (isOffice
            ? 'Office visit in progress'
            : 'Rider collection in progress');
    final color = isPendingRequest ? AppColors.warning : AppColors.lenderBlue;

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

/// Skeletal loading na kamukha ng schedule layout: navy summary header
/// (3 columns) + listahan ng schedule tiles.
class _PaymentScheduleSkeleton extends StatelessWidget {
  const _PaymentScheduleSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Column(
        children: [
          // Summary header placeholder
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            color: AppColors.lenderBlue.withValues(alpha: 0.25),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                3,
                (_) => Column(
                  children: [
                    Container(
                      width: 60,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 80,
                      height: 13,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Schedule tiles placeholder
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                children: List.generate(
                  6,
                  (_) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 130,
                                height: 13,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: 160,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              width: 64,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 48,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
