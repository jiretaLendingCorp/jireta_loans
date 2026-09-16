// lib/presentation/features/head_manager/loans/widgets/approve_reject_modal.dart
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

class ApproveRejectModal extends StatefulWidget {
  final String loanId;
  final bool isApprove;
  final void Function(String loanId, String? reason) onConfirm;

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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _confirm,
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
    widget.onConfirm(widget.loanId, null);
  }
}
