// lib/presentation/features/head_manager/loans/widgets/approve_reject_modal.dart
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import 'loan_reapply_picker.dart';

class ApproveRejectModal extends StatefulWidget {
  final String loanId;
  final bool isApprove;

  /// [reapplyAllowedAt] — 00176: kailan pwedeng mag-apply ulit ang lender
  /// (pinili sa [LoanReapplyPicker]). Kapag `isApprove` ito ay null —
  /// rejection lang ang may re-apply window.
  final void Function(String loanId, String? reason, DateTime? reapplyAllowedAt)
      onConfirm;

  const ApproveRejectModal({
    super.key,
    required this.loanId,
    required this.isApprove,
    required this.onConfirm,
  });

  @override
  State<ApproveRejectModal> createState() => _ApproveRejectModalState();
}

class _ApproveRejectModalState extends State<ApproveRejectModal> {
  bool _loading = false;

  /// Napiling re-apply date para sa rejection. WALANG default: mananatili
  /// itong null hangga't hindi pumili ang staff, at habang null ay
  /// naka-disable ang Reject (para hindi ito tahimik na mag-fallback sa
  /// 1-month default).
  DateTime? _reapplyAllowedAt;

  /// True kapag may pinili nang re-apply date ang staff (kasama ang
  /// "Immediately", na `DateTime.now()`).
  bool get _reapplyChosen => _reapplyAllowedAt != null;

  @override
  Widget build(BuildContext context) {
    final color = widget.isApprove ? AppColors.success : AppColors.error;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            widget.isApprove
                ? Icons.check_circle_outline
                : Icons.cancel_outlined,
            color: color,
            size: 24,
          ),
          const SizedBox(width: 10),
          Text(widget.isApprove ? 'Approve Loan' : 'Reject Loan'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isApprove
                  ? 'Are you sure you want to approve this loan application? This will proceed to disbursement.'
                  : 'Are you sure to reject this loan application? This action cannot be undone.',
              style:
                  const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            // 00176: kapag rejection, ang staff ang nagde-decide kung kailan
            // pwedeng mag-apply ulit ang lender (walang approve-side chooser).
            if (!widget.isApprove) ...[
              const Divider(height: 26),
              LoanReapplyPicker(
                onChanged: (date) {
                  if (mounted) setState(() => _reapplyAllowedAt = date);
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          // Pag-reject, kailangan munang pumili ng re-apply date — walang
          // default na 1 month, desisyon ito ng staff.
          onPressed: (_loading || (!widget.isApprove && !_reapplyChosen))
              ? null
              : _confirm,
          style: ElevatedButton.styleFrom(
              backgroundColor: color, foregroundColor: Colors.white),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(widget.isApprove ? 'Approve' : 'Reject'),
        ),
      ],
    );
  }

  Future<void> _confirm() async {
    setState(() => _loading = true);
    // No reason collected — a plain Yes/No confirmation (reason stays null).
    // Ang re-apply date naman ay pinipili ng staff (null kapag approve).
    widget.onConfirm(
      widget.loanId,
      null,
      widget.isApprove ? null : _reapplyAllowedAt,
    );
  }
}
