// lib/presentation/features/employee/payments/widgets/record_office_payment_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/helpers.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../providers/emp_payment_provider.dart';

class RecordOfficePaymentModal extends ConsumerStatefulWidget {
  final VoidCallback onRecorded;
  final String? loanId;
  final String? loanScheduleId;
  final double? amount;
  final String? assignmentId;
  const RecordOfficePaymentModal({
    super.key,
    required this.onRecorded,
    this.loanId,
    this.loanScheduleId,
    this.amount,
    this.assignmentId,
  });

  @override
  ConsumerState<RecordOfficePaymentModal> createState() =>
      _RecordOfficePaymentModalState();
}

class _RecordOfficePaymentModalState
    extends ConsumerState<RecordOfficePaymentModal> {
  late final _loanIdCtrl = TextEditingController(text: widget.loanId ?? '');
  late final _scheduleIdCtrl =
      TextEditingController(text: widget.loanScheduleId ?? '');
  late final _amountCtrl = TextEditingController(
      text: widget.amount != null ? widget.amount!.toStringAsFixed(2) : '');
  final _notesCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _loanIdCtrl.dispose();
    _scheduleIdCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final loanId = _loanIdCtrl.text.trim();
    final scheduleId = _scheduleIdCtrl.text.trim();
    final amountStr = _amountCtrl.text.trim();

    if (loanId.isEmpty || scheduleId.isEmpty || amountStr.isEmpty) {
      setState(() => _error = 'All required fields must be filled.');
      return;
    }
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final idempotencyKey = AppHelpers.generateIdempotencyKey();
    final ok = await ref
        .read(empPaymentListProvider.notifier)
        .recordOfficePayment(
          loanId: loanId,
          loanScheduleId: scheduleId,
          amount: amount,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          assignmentId: widget.assignmentId,
          idempotencyKey: idempotencyKey,
        );

    setState(() => _loading = false);
    if (ok && mounted) {
      Navigator.of(context).pop();
      widget.onRecorded();
    } else if (mounted) {
      setState(() => _error = 'Failed to record payment. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      color: AppColors.deepNavy),
                  const SizedBox(width: 10),
                  const Text('Record Office Payment',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepNavy)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppColors.info),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Verify the lender\'s account upgrade identity before recording payment.',
                        style: TextStyle(fontSize: 12, color: AppColors.info),
                      ),
                    ),
                  ],
                ),
              ),
              AppTextField(
                controller: _loanIdCtrl,
                label: 'Loan ID *',
                hint: 'Enter the loan UUID',
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _scheduleIdCtrl,
                label: 'Loan Schedule ID *',
                hint: 'Enter the installment UUID',
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _amountCtrl,
                label: 'Amount (₱) *',
                hint: '0.00',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                maxLength: 12,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _notesCtrl,
                label: 'Notes (optional)',
                maxLines: 2,
                maxLength: 255,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 16, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.error)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deepNavy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Record Payment'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
