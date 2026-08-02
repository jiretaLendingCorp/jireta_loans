// lib/presentation/features/head_manager/payments/widgets/reverse_payment_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../providers/hm_payment_provider.dart';

class ReversePaymentModal extends ConsumerStatefulWidget {
  final Map<String, dynamic> payment;
  const ReversePaymentModal({super.key, required this.payment});

  @override
  ConsumerState<ReversePaymentModal> createState() =>
      _ReversePaymentModalState();
}

class _ReversePaymentModalState extends ConsumerState<ReversePaymentModal> {
  final _reasonCtrl = TextEditingController();
  bool _loading = false;
  bool _confirmed = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reasonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please provide a reason for reversal');
      return;
    }
    if (!_confirmed) {
      setState(
          () => _error = 'Please confirm you want to reverse this payment');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(hmPaymentProvider.notifier).reversePayment(
            paymentId: widget.payment['id'] as String,
            reason: _reasonCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = (widget.payment['amount'] as num?)?.toDouble() ?? 0;
    final ref2 = widget.payment['xendit_reference'] ??
        widget.payment['idempotency_key'] ??
        '—';

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.undo_outlined,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text('Reverse Payment',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700))),
                  IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close,
                          color: Colors.white70, size: 20)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Amount',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary)),
                            Text(amount.toCurrency,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Reference',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary)),
                            Text(ref2,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '⚠️ This action will reverse the payment and restore the loan balance. This cannot be undone.',
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _reasonCtrl,
                    label: 'Reason for Reversal *',
                    hint: 'Explain why this payment is being reversed...',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: _confirmed,
                        onChanged: (v) => setState(() => _confirmed = v!),
                        activeColor: AppColors.error,
                      ),
                      const Expanded(
                        child: Text(
                          'I confirm this payment reversal and understand it cannot be undone',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.3))),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: _loading
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Text('Cancel'))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: AppButton(
                              label: 'Reverse Payment',
                              onPressed: _loading ? null : _submit,
                              isLoading: _loading,
                              color: AppColors.error)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
