// lib/presentation/features/head_manager/reports/widgets/generate_report_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/forms/app_date_range_picker.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../providers/hm_report_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class GenerateReportModal extends ConsumerStatefulWidget {
  final Map<String, dynamic> template;

  const GenerateReportModal({super.key, required this.template});

  static Future<bool?> show(
    BuildContext context, {
    required Map<String, dynamic> template,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GenerateReportModal(template: template),
    );
  }

  @override
  ConsumerState<GenerateReportModal> createState() =>
      _GenerateReportModalState();
}

class _GenerateReportModalState extends ConsumerState<GenerateReportModal> {
  DateTimeRange? _dateRange;
  String _format = 'pdf';
  bool _submitting = false;
  String? _selectedStatus;

  final List<String> _statusOptions = [
    'All',
    'pending',
    'under_review',
    'approved',
    'active',
    'completed',
    'overdue',
    'rejected',
  ];

  String get _templateKey => widget.template['template_key'] as String? ?? '';
  String get _templateName => widget.template['name'] as String? ?? 'Report';
  String get _templateDescription =>
      widget.template['description'] as String? ?? '';

  Future<void> _generate() async {
    if (_dateRange == null) {
      context.showSnackBarAsToast(
        const SnackBar(content: Text('Please select a date range')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final params = {
        'date_from': DateFormat('yyyy-MM-dd').format(_dateRange!.start),
        'date_to': DateFormat('yyyy-MM-dd').format(_dateRange!.end),
        'format': _format,
        if (_selectedStatus != null && _selectedStatus != 'All')
          'status': _selectedStatus,
      };

      await ref
          .read(hmReportProvider.notifier)
          .generateReport(_templateKey, params);

      if (!mounted) return;
      Navigator.of(context).pop(true);
      await SuccessDialog.show(
        context,
        title: 'Report Generated',
        message:
            '$_templateName has been generated successfully. Check Report History to download.',
      );
    } catch (e) {
      if (!mounted) return;
      await ErrorDialog.show(
        context,
        title: 'Generation Failed',
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
        constraints: const BoxConstraints(maxWidth: 520),
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
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.picture_as_pdf_outlined,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Generate Report',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          _templateName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              if (_templateDescription.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    _templateDescription,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'Date Range',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              AppDateRangePicker(
                value: _dateRange,
                onChanged: (range) => setState(() => _dateRange = range),
              ),
              const SizedBox(height: 16),
              const Text(
                'Filter by Status',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedStatus ?? 'All',
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: _statusOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedStatus = v),
              ),
              const SizedBox(height: 16),
              const Text(
                'Export Format',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _FormatChip(
                    label: 'PDF',
                    icon: Icons.picture_as_pdf,
                    selected: _format == 'pdf',
                    onTap: () => setState(() => _format = 'pdf'),
                    color: Colors.red,
                  ),
                  const SizedBox(width: 12),
                  _FormatChip(
                    label: 'Excel',
                    icon: Icons.table_chart,
                    selected: _format == 'xlsx',
                    onTap: () => setState(() => _format = 'xlsx'),
                    color: Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    label: _submitting ? 'Generating...' : 'Generate Report',
                    onPressed: _submitting ? null : _generate,
                    isLoading: _submitting,
                    icon: Icons.download_outlined,
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

class _FormatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FormatChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : AppColors.surface,
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected ? color : AppColors.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
