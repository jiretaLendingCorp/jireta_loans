// lib/presentation/shared/widgets/pending_payments_table.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/di/injection.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/helpers.dart';
import '../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../data/models/collection_assignment_model.dart';
import 'dialogs/office_payment_dialog.dart';
import 'layout/responsive_content.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

/// "All Pending Payment" table — Collections (Head Manager at Employee).
///
/// Ipinapakita ang LAHAT ng koleksyong hindi pa bayad / hindi pa naka-kolekta
/// (requested · assigned · accepted · in_progress · pending_approval) — kasama
/// na ang mga lender na sa **office** magbabayad at hinihintay pa lang.
///
/// Sa mga request na `type = office`, may **Paid in Office** button: nire-record
/// nito ang walk-in payment (`payments-manage?fn=record-office`, kasama ang
/// `assignment_id`) — lumalabas ang verified na office_cash payment, bumababa
/// ang balance, nagiging `completed` ang request, at nabibigyan ng
/// notification ang lender.
class PendingPaymentsTable extends StatefulWidget {
  final List<CollectionAssignmentModel> items;

  /// Tinatawag pagkatapos ng matagumpay na record — para ma-refresh ng screen
  /// ang listahan at ang payments table nito.
  final Future<void> Function()? onRefresh;

  /// View action (naka-scope sa role ng screen na gumagamit).
  final void Function(CollectionAssignmentModel item)? onView;

  const PendingPaymentsTable({
    super.key,
    required this.items,
    this.onRefresh,
    this.onView,
  });

  @override
  State<PendingPaymentsTable> createState() => _PendingPaymentsTableState();
}

class _PendingPaymentsTableState extends State<PendingPaymentsTable> {
  String? _recordingId;

  static const _payableStatusBlocklist = [
    'completed',
    'rejected',
    'declined',
    'failed',
  ];

  double _payableAmount(CollectionAssignmentModel c) {
    final requested = c.requestedAmount ?? 0;
    if (requested > 0) return requested;
    final collected = c.amountCollected ?? 0;
    if (collected > 0) return collected;
    return c.amountDue;
  }

  String _loanId(CollectionAssignmentModel c) =>
      (c.loanSchedule?['loan']?['id'] as String?) ??
      (c.loanSchedule?['loan_id'] as String?) ??
      '';

  bool _isOffice(CollectionAssignmentModel c) => c.collectionType == 'office';

  bool _canMarkPaid(CollectionAssignmentModel c) =>
      _isOffice(c) && !_payableStatusBlocklist.contains(c.status);

  Future<void> _markPaidInOffice(CollectionAssignmentModel c) async {
    final loanId = _loanId(c);
    final amount = _payableAmount(c);
    final loanScheduleId = c.loanScheduleId;

    if (loanId.isEmpty || loanScheduleId.isEmpty || amount <= 0) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text(
              'Missing loan or installment info for this request. Please refresh and try again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final paid = await showOfficePaymentDialog(
      context,
      lenderName: c.lenderName,
      loanNumber: c.loanNumber,
      amount: amount,
    );
    if (paid == null || paid <= 0 || !mounted) return;

    setState(() => _recordingId = c.id);
    String? error;
    var ok = false;
    try {
      await sl<PaymentRemoteDataSource>().recordOfficePayment(
        loanId: loanId,
        loanScheduleId: loanScheduleId,
        amount: paid,
        assignmentId: c.id,
        notes: 'Paid in office',
        idempotencyKey: AppHelpers.generateIdempotencyKey(),
      );
      ok = true;
    } catch (e) {
      error = ErrorHandler.handle(e).message;
    }
    if (!mounted) return;
    setState(() => _recordingId = null);

    // Refresh — best effort, hindi dapat mag-report ng failure kung ang bayad
    // ay matagumpay nang naitala.
    try {
      await widget.onRefresh?.call();
    } catch (_) {}

    if (!mounted) return;
    context.showSnackBarAsToast(
      SnackBar(
        content: Text(ok
            ? 'Marked as paid in office — ${paid.toStringAsFixed(2)} recorded'
            : (error ?? 'Failed to mark as paid in office')),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final dateFmt = DateFormat('MMM dd, yyyy');

    return ResponsiveListCard(
      minTableWidth: 940,
      columns: const [
        ResponsiveCol('Lender & Loan', icon: Icons.person_outline, flex: 3),
        ResponsiveCol('Amount Due',
            icon: Icons.payments_outlined, flex: 2),
        ResponsiveCol('Type', icon: Icons.account_balance_wallet_outlined, flex: 2),
        ResponsiveCol('Due Date', icon: Icons.event_outlined, flex: 2),
        ResponsiveCol('Requested', icon: Icons.schedule_outlined, flex: 2),
        ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 2),
      ],
      actionsCol: const ResponsiveActionsCol(width: 210),
      rows: widget.items.map((c) {
        final accent = _accentForStatus(c.status);
        final amount = _payableAmount(c);
        final dueDate = c.loanSchedule?['due_date']?.toString();
        final requested =
            c.effectiveRequestedAt ?? c.createdAt;
        return ResponsiveRow(
          cells: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.lenderName.isEmpty ? 'Unknown lender' : c.lenderName,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  c.loanNumber.isEmpty ? '—' : c.loanNumber,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            Text(
              '₱${fmt.format(amount)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: amount > 0
                    ? AppColors.deepNavy
                    : AppColors.textSecondary,
              ),
            ),
            Row(
              children: [
                Icon(
                  _isOffice(c)
                      ? Icons.storefront_rounded
                      : Icons.delivery_dining_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    c.collectionTypeLabel,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              dueDate == null || dueDate.isEmpty
                  ? '—'
                  : _formatDate(dueDate, dateFmt),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            Text(
              dateFmt.format(requested),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _statusLabel(c.status),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionButton(
                label: 'View',
                icon: Icons.visibility_outlined,
                onTap: widget.onView == null
                    ? null
                    : () => widget.onView!(c),
              ),
              // Office requests lang — dito nila "babayaran sa office".
              if (_canMarkPaid(c)) ...[
                const SizedBox(width: 6),
                _ActionButton(
                  label: 'Paid in Office',
                  icon: Icons.storefront_rounded,
                  filled: true,
                  color: AppColors.success,
                  busy: _recordingId == c.id,
                  onTap: () => _markPaidInOffice(c),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  static String _formatDate(String raw, DateFormat fmt) {
    try {
      return fmt.format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'requested':
        return 'Requested';
      case 'assigned':
        return 'Rider Assigned';
      case 'accepted':
        return 'Accepted';
      case 'in_progress':
        return 'In Progress';
      case 'pending_approval':
        return 'Pending Approval';
      default:
        return status
            .split('_')
            .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
  }

  static Color _accentForStatus(String s) {
    switch (s) {
      case 'requested':
      case 'pending_approval':
        return AppColors.warning;
      case 'assigned':
        return AppColors.lenderBlue;
      case 'accepted':
        return AppColors.riderGreen;
      case 'in_progress':
        return const Color(0xFFFFA000);
      case 'completed':
        return AppColors.riderGreen;
      case 'rejected':
      case 'failed':
      case 'declined':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool busy;
  final Color color;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.busy = false,
    this.color = AppColors.deepNavy,
  });

  @override
  Widget build(BuildContext context) {
    final effective = busy ? color.withValues(alpha: 0.7) : color;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? effective : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: filled ? effective : AppColors.border,
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 14, color: filled ? Colors.white : color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: filled ? Colors.white : color,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
