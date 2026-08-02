// lib/presentation/features/head_manager/in_office/widgets/step3_loan_details.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../domain/repositories/i_loan_repository.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';

class Step3LoanDetails extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onDataChanged;

  const Step3LoanDetails({
    super.key,
    required this.data,
    required this.onDataChanged,
  });

  @override
  ConsumerState<Step3LoanDetails> createState() => _Step3LoanDetailsState();
}

class _Step3LoanDetailsState extends ConsumerState<Step3LoanDetails> {
  final _amountCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  String _frequency = 'monthly';
  Map<String, dynamic>? _preview;
  bool _loadingPreview = false;
  String? _previewError;

  static const double _minAmount = 3000;
  static const double _maxAmount = 500000;

  double get _amount =>
      double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    if (_amount < _minAmount || _amount > _maxAmount) return;

    setState(() {
      _loadingPreview = true;
      _previewError = null;
    });

    try {
      final repo = sl<ILoanRepository>();
      final preview = await repo.getSchedulePreview(
        principal: _amount,
        frequency: _frequency,
      );
      setState(() => _preview = preview as Map<String, dynamic>?);
      _update();
    } catch (e) {
      setState(() =>
          _previewError = 'Could not load preview. Please check the amount.');
    } finally {
      setState(() => _loadingPreview = false);
    }
  }

  void _update() {
    widget.onDataChanged({
      'amount': _amount,
      'frequency': _frequency,
      'purpose': _purposeCtrl.text.trim(),
      'schedule_preview': _preview,
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Loan Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'All calculations are performed server-side. No Dart math is used.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _amountCtrl,
            label: 'Loan Amount (₱3,000 – ₱500,000) *',
            keyboardType: TextInputType.number,
            prefixIcon: Icons.attach_money,
            onChanged: (_) {
              _update();
              if (_amount >= _minAmount && _amount <= _maxAmount) {
                _loadPreview();
              }
            },
          ),
          const SizedBox(height: 8),
          if (_amount > 0 && (_amount < _minAmount || _amount > _maxAmount))
            const Text(
              'Amount must be between ₱3,000 and ₱500,000',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          const SizedBox(height: 16),
          const Text(
            'Payment Frequency *',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _FreqChip(
                label: 'Daily',
                icon: Icons.calendar_today,
                selected: _frequency == 'daily',
                onTap: () {
                  setState(() => _frequency = 'daily');
                  _update();
                  _loadPreview();
                },
              ),
              const SizedBox(width: 10),
              _FreqChip(
                label: 'Weekly',
                icon: Icons.date_range,
                selected: _frequency == 'weekly',
                onTap: () {
                  setState(() => _frequency = 'weekly');
                  _update();
                  _loadPreview();
                },
              ),
              const SizedBox(width: 10),
              _FreqChip(
                label: 'Monthly',
                icon: Icons.calendar_month,
                selected: _frequency == 'monthly',
                onTap: () {
                  setState(() => _frequency = 'monthly');
                  _update();
                  _loadPreview();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _purposeCtrl,
            label: 'Purpose of Loan',
            maxLines: 3,
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 24),
          if (_loadingPreview) const Center(child: CircularProgressIndicator()),
          if (_previewError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                _previewError!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ),
          if (_preview != null && !_loadingPreview) ...[
            const Text(
              'Loan Schedule Preview',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.04),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _PreviewRow(
                    label: 'Principal Amount',
                    value: (_preview!['principal'] as num? ?? _amount)
                        .toDouble()
                        .toCurrency,
                  ),
                  const Divider(height: 16),
                  _PreviewRow(
                    label: 'Interest (20%)',
                    value: (_preview!['interest'] as num? ?? 0)
                        .toDouble()
                        .toCurrency,
                    valueColor: AppColors.error,
                  ),
                  _PreviewRow(
                    label: 'Total Payable',
                    value: (_preview!['total_payable'] as num? ?? 0)
                        .toDouble()
                        .toCurrency,
                    bold: true,
                    valueColor: AppColors.primary,
                  ),
                  const Divider(height: 16),
                  _PreviewRow(
                    label: 'Term',
                    value: '${_preview!['term_days'] ?? 0} days',
                  ),
                  _PreviewRow(
                    label: 'Installment Amount',
                    value: (_preview!['installment_amount'] as num? ?? 0)
                        .toDouble()
                        .toCurrency,
                    bold: true,
                    valueColor: AppColors.gold,
                  ),
                  _PreviewRow(
                    label: 'Number of Payments',
                    value: '${(_preview!['due_dates'] as List?)?.length ?? 0}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if ((_preview!['due_dates'] as List?)?.isNotEmpty == true) ...[
              const Text(
                'Payment Schedule',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ListView.separated(
                    itemCount: (_preview!['due_dates'] as List).length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, i) {
                      final dates = _preview!['due_dates'] as List;
                      final amounts = _preview!['amounts'] as List;
                      final date = dates[i] as String? ?? '';
                      final amt = (amounts[i] as num? ?? 0).toDouble();
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        title: Text(
                          date,
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: Text(
                          amt.toCurrency,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _FreqChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FreqChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.08)
                : AppColors.surface,
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.border,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.gold : AppColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _PreviewRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
