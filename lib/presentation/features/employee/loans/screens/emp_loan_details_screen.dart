// lib/presentation/features/employee/loans/screens/emp_loan_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/emp_loan_provider.dart';

final _loanDetailProvider =
    FutureProvider.family<LoanModel, String>((ref, id) async {
  return ref.read(empLoanProvider.notifier).getDetails(id);
});

class EmpLoanDetailsScreen extends ConsumerWidget {
  final String loanId;
  const EmpLoanDetailsScreen({super.key, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loanAsync = ref.watch(_loanDetailProvider(loanId));

    return WebScaffold(
      title: 'Loan Details',
      body: loanAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: ShimmerLoader(height: 400),
        ),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text('Failed to load loan: $e',
                style: const TextStyle(color: AppColors.textSecondary)),
          ]),
        ),
        data: (loan) => _LoanDetailBody(loan: loan, loanId: loanId),
      ),
    );
  }
}

class _LoanDetailBody extends ConsumerStatefulWidget {
  final LoanModel loan;
  final String loanId;
  const _LoanDetailBody({required this.loan, required this.loanId});

  @override
  ConsumerState<_LoanDetailBody> createState() => _LoanDetailBodyState();
}

class _LoanDetailBodyState extends ConsumerState<_LoanDetailBody> {
  final _reasonCtrl = TextEditingController();
  bool _isActing = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.statusPending;
      case 'under_review':
        return AppColors.info;
      case 'ci_required':
      case 'ci_assigned':
      case 'ci_completed':
        return AppColors.warning;
      case 'approved':
        return AppColors.success;
      case 'active':
        return AppColors.statusActive;
      case 'completed':
        return AppColors.statusCompleted;
      case 'rejected':
      case 'cancelled':
        return AppColors.error;
      case 'overdue':
        return AppColors.statusOverdue;
      default:
        return AppColors.textTertiary;
    }
  }

  bool get _canApprove => [
        'pending',
        'under_review',
        'ci_required',
        'ci_assigned',
        'ci_completed'
      ].contains(widget.loan.status);
  bool get _canReject => [
        'pending',
        'under_review',
        'ci_required',
        'ci_assigned',
        'ci_completed'
      ].contains(widget.loan.status);
  bool get _canRequestCI => widget.loan.status == 'under_review';

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(loan),
        const SizedBox(height: 20),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              flex: 2,
              child: Column(children: [
                _buildLoanCard(loan),
                const SizedBox(height: 16),
                _buildScheduleCard(loan),
              ])),
          const SizedBox(width: 16),
          Expanded(
              child: Column(children: [
            _buildLenderCard(loan),
            const SizedBox(height: 16),
            _buildActionsCard(loan),
          ])),
        ]),
      ]),
    );
  }

  Widget _buildHeader(LoanModel loan) {
    final color = _statusColor(loan.status);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(colors: [AppColors.deepNavy, AppColors.navyLight]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
          ),
          child: const Icon(Icons.description_outlined,
              color: AppColors.gold, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(loan.loanNumber,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFamily: 'PlayfairDisplay')),
          const SizedBox(height: 4),
          Text('Lender: ${loan.lenderName ?? 'N/A'}',
              style: TextStyle(
                  fontSize: 13, color: Colors.white.withValues(alpha: 0.7))),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(loan.status.toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
        ),
      ]),
    );
  }

  Widget _buildLoanCard(LoanModel loan) {
    return _InfoCard(
        title: 'Loan Information',
        icon: Icons.account_balance_wallet_outlined,
        children: [
          _InfoRow('Loan Number', loan.loanNumber),
          _InfoRow('Principal', loan.principalAmount.toCurrency),
          _InfoRow('Interest Rate', '${loan.interestRate.toStringAsFixed(0)}%'),
          _InfoRow('Interest Amount', loan.interestAmount.toCurrency),
          _InfoRow('Total Payable', loan.totalPayable.toCurrency,
              valueColor: AppColors.deepNavy),
          _InfoRow('Outstanding Balance', loan.outstandingBalance.toCurrency,
              valueColor: AppColors.warning),
          _InfoRow('Payment Frequency', loan.frequency.toUpperCase()),
          _InfoRow('Term', '${loan.termDays} days'),
          if (loan.dueDate != null)
            _InfoRow('Due Date', loan.dueDate!.toDisplayDate),
          if (loan.disbursedAt != null)
            _InfoRow('Disbursed', loan.disbursedAt!.toDisplayDate),
          if (loan.rejectionReason != null)
            _InfoRow('Rejection Reason', loan.rejectionReason!,
                valueColor: AppColors.error),
        ]);
  }

  Widget _buildScheduleCard(LoanModel loan) {
    final schedules = loan.schedules ?? [];
    if (schedules.isEmpty) return const SizedBox.shrink();
    return _InfoCard(
        title: 'Payment Schedule',
        icon: Icons.calendar_today_outlined,
        children: [
          const SizedBox(height: 8),
          Table(
            border: TableBorder.all(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(8)),
            columnWidths: const {
              0: FlexColumnWidth(0.8),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1)
            },
            children: [
              TableRow(
                  decoration:
                      const BoxDecoration(color: AppColors.surfaceVariant),
                  children: [
                    for (final h in ['#', 'Due Date', 'Amount', 'Status'])
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Text(h,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: AppColors.textSecondary))),
                  ]),
              for (final (i, s) in schedules.indexed)
                TableRow(children: [
                  _td('${i + 1}'),
                  _td(s['due_date'] ?? '—'),
                  _td((s['amount_due'] as num?)?.toDouble().toCurrency ?? '—'),
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: StatusBadge(status: s['status'] ?? 'pending')),
                ]),
            ],
          ),
        ]);
  }

  Widget _td(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(text, style: const TextStyle(fontSize: 12)));

  Widget _buildLenderCard(LoanModel loan) {
    final lp = loan.lenderProfile;
    return _InfoCard(
        title: 'Lender Information',
        icon: Icons.person_outline,
        children: [
          _InfoRow('Name', loan.lenderName ?? 'N/A'),
          if (lp != null) ...[
            _InfoRow('Account Upgrade Status', lp['account_upgrade_status'] ?? 'N/A'),
            _InfoRow('Employment', lp['employment_type'] ?? 'N/A'),
            _InfoRow('Monthly Income',
                (lp['monthly_income'] as num?)?.toDouble().toCurrency ?? 'N/A'),
          ],
        ]);
  }

  Widget _buildActionsCard(LoanModel loan) {
    return _InfoCard(
        title: 'Actions',
        icon: Icons.flash_on_outlined,
        children: [
          const SizedBox(height: 8),
          if (_canApprove) ...[
            SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isActing
                      ? null
                      : () => _confirm(context, 'Approve Loan',
                              'Are you sure you want to approve ${loan.loanNumber}?',
                              () async {
                            await ref
                                .read(empLoanProvider.notifier)
                                .approveLoan(widget.loanId);
                            if (mounted) Navigator.of(context).pop();
                          }),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Approve Loan'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white),
                )),
            const SizedBox(height: 8),
          ],
          if (_canReject) ...[
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      _isActing ? null : () => _showRejectDialog(context, loan),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Reject Loan'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error)),
                )),
            const SizedBox(height: 8),
          ],
          if (_canRequestCI) ...[
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isActing
                      ? null
                      : () => _confirm(context, 'Request CI',
                              'Request credit investigation for ${loan.loanNumber}?',
                              () async {
                            await ref
                                .read(empLoanProvider.notifier)
                                .requestCi(widget.loanId);
                            if (mounted) Navigator.of(context).pop();
                          }),
                  icon: const Icon(Icons.search_outlined, size: 18),
                  label: const Text('Request CI'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                      side: const BorderSide(color: AppColors.info)),
                )),
          ],
          if (!_canApprove && !_canReject && !_canRequestCI)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('No actions available for this loan status.',
                  style:
                      TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            ),
        ]);
  }

  Future<void> _confirm(BuildContext ctx, String title, String msg,
      Future<void> Function() action) async {
    final ok = await showDialog<bool>(
        context: ctx,
        builder: (_) => AlertDialog(
              title: Text(title),
              content: Text(msg),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Confirm')),
              ],
            ));
    if (ok == true) {
      setState(() => _isActing = true);
      await action();
      setState(() => _isActing = false);
    }
  }

  void _showRejectDialog(BuildContext ctx, LoanModel loan) {
    _reasonCtrl.clear();
    showDialog(
        context: ctx,
        builder: (_) => AlertDialog(
              title: const Text('Reject Loan'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Rejecting ${loan.loanNumber}. Please provide a reason:'),
                const SizedBox(height: 12),
                TextField(
                  controller: _reasonCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Enter rejection reason...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error),
                  onPressed: () async {
                    if (_reasonCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    setState(() => _isActing = true);
                    await ref
                        .read(empLoanProvider.notifier)
                        .rejectLoan(widget.loanId, _reasonCtrl.text.trim());
                    setState(() => _isActing = false);
                  },
                  child: const Text('Reject'),
                ),
              ],
            ));
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _InfoCard(
      {required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.deepNavy),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ]),
          const Divider(height: 20),
          ...children,
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
            flex: 2,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary))),
        Expanded(
            flex: 3,
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? AppColors.textPrimary))),
      ]),
    );
  }
}
