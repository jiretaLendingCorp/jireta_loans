// lib/presentation/features/head_manager/loans/widgets/approve_reject_modal.dart
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import 'loan_reapply_picker.dart';

class ApproveRejectModal extends StatefulWidget {
  final String loanId;
  final bool isApprove;

  /// [reapplyAllowedAt] / [permanent] — 00176 / 00179: kailan pwedeng mag-apply
  /// ulit ang lender (pinili sa [LoanReapplyPicker]). `permanent = true` =
  /// hindi na makakapag-apply muli ang lender. Kapag `isApprove`, ang dalawang
  /// ito ay null/false — rejection lang ang may re-apply window.
  final void Function(
      String loanId, String? reason, DateTime? reapplyAllowedAt,
      bool permanent) onConfirm;

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

  /// Napili ng staff para sa rejection (date o permanent). WALANG default:
  /// mananatili itong null hangga't hindi pumili ang staff, at habang null ay
  /// naka-disable ang Reject (para hindi ito tahimik na mag-fallback sa
  /// 1-month default).
  LoanReapplyChoice? _reapplyChoice;

  /// True kapag may pinili nang opsyon ang staff (kasama ang "Immediately",
  /// na `DateTime.now()`, at ang "Permanent reject").
  bool get _reapplyChosen => _reapplyChoice != null;

  /// True kapag permanenteng rejection ang pinili — hindi na makakapag-apply
  /// muli ang lender.
  bool get _permanent => _reapplyChoice?.permanent ?? false;

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
      // Naka-scroll: anim na pagpipilian + buod ang nasa loob, kaya hindi ito
      // sumasabog sa mababang screen.
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isApprove
                    ? 'Are you sure you want to approve this loan application? This will proceed to disbursement.'
                    : 'Are you sure to reject this loan application? This action cannot be undone.',
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
              // 00176 / 00179: kapag rejection, ang staff ang nagde-decide kung
              // kailan pwedeng mag-apply ulit ang lender — o kung PERMANENTE
              // nang hindi na ito papayagan (walang approve-side chooser).
              if (!widget.isApprove) ...[
                const Divider(height: 26),
                LoanReapplyPicker(
                  onChanged: (choice) {
                    if (mounted) setState(() => _reapplyChoice = choice);
                  },
                ),
              ],
            ],
          ),
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
              : Text(widget.isApprove
                  ? 'Approve'
                  : _permanent
                      ? 'Reject permanently'
                      : 'Reject'),
        ),
      ],
    );
  }

  Future<void> _confirm() async {
    setState(() => _loading = true);
    // No reason collected — a plain Yes/No confirmation (reason stays null).
    // Ang re-apply date (o permanent) naman ay pinipili ng staff — null/false
    // kapag approve.
    widget.onConfirm(
      widget.loanId,
      null,
      widget.isApprove ? null : _reapplyChoice?.allowedAt,
      !widget.isApprove && _permanent,
    );
  }
}
