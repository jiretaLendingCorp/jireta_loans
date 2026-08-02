// lib/presentation/features/head_manager/loans/widgets/penalty_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../providers/hm_loan_provider.dart';

class PenaltyModal extends ConsumerStatefulWidget {
  final String loanId;
  final double totalPayable;
  final String loanNumber;

  const PenaltyModal({
    super.key,
    required this.loanId,
    required this.totalPayable,
    required this.loanNumber,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String loanId,
    required double totalPayable,
    required String loanNumber,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PenaltyModal(
        loanId: loanId,
        totalPayable: totalPayable,
        loanNumber: loanNumber,
      ),
    );
  }

  @override
  ConsumerState<PenaltyModal> createState() => _PenaltyModalState();
}

class _PenaltyModalState extends ConsumerState<PenaltyModal> {
  bool _submitting = false;
  final double _penaltyRate = 0.20;

  double get _penaltyAmount => widget.totalPayable * _penaltyRate;
  double get _newTotal => widget.totalPayable + _penaltyAmount;

  Future<void> _applyPenalty() async {
    setState(() => _submitting = true);
    try {
      await ref.read(hmLoanProvider.notifier).applyPenalty(widget.loanId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      await SuccessDialog.show(
        context,
        title: 'Penalty Applied',
        message:
            'A 20% penalty of ${_penaltyAmount.toCurrency} has been applied to loan ${widget.loanNumber}.',
      );
    } catch (e) {
      if (!mounted) return;
      await ErrorDialog.show(
        context,
        title: 'Failed to Apply Penalty',
        message: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: AppColors.error, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Apply Overdue Penalty',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Loan ${widget.loanNumber}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _Row(
                      label: 'Current Total Payable',
                      value: widget.totalPayable.toCurrency,
                    ),
                    const Divider(height: 20),
                    const _Row(
                      label: 'Penalty Rate',
                      value: '20%',
                      valueColor: AppColors.error,
                    ),
                    const SizedBox(height: 8),
                    _Row(
                      label: 'Penalty Amount',
                      value: _penaltyAmount.toCurrency,
                      valueColor: AppColors.error,
                      bold: true,
                    ),
                    const Divider(height: 20),
                    _Row(
                      label: 'New Total Payable',
                      value: _newTotal.toCurrency,
                      valueColor: AppColors.primary,
                      bold: true,
                      large: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.amber, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action cannot be undone. Penalty is applied only when the loan is overdue by one month.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    label: _submitting ? 'Applying...' : 'Apply Penalty',
                    onPressed: _submitting ? null : _applyPenalty,
                    variant: AppButtonVariant.danger,
                    isLoading: _submitting,
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

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final bool large;

  const _Row({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: large ? 14 : 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            fontSize: large ? 16 : 14,
          ),
        ),
      ],
    );
  }
}
