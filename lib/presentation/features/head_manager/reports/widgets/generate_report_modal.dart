// lib/presentation/features/head_manager/reports/widgets/generate_report_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
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
    final accent = _accentForTemplate(_templateKey);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 32, offset: const Offset(0, 12))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Premium header with gradient
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, accent.withValues(alpha: 0.82)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Generate Report', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                            const SizedBox(height: 2),
                            Text(_templateName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                            if (_templateDescription.isNotEmpty)
                              Text(_templateDescription, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Date Range', Icons.date_range_rounded),
                        const SizedBox(height: 8),
                        AppDateRangePicker(
                          value: _dateRange,
                          onChanged: (range) => setState(() => _dateRange = range),
                        ),
                        const SizedBox(height: 18),
                        _buildLabel('Filter by Status', Icons.filter_list_rounded),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedStatus ?? 'All',
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppColors.surfaceVariant,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accent, width: 1.4)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                          onChanged: (v) => setState(() => _selectedStatus = v),
                        ),
                        const SizedBox(height: 18),
                        _buildLabel('Export Format', Icons.file_download_rounded),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _FormatCard(
                                label: 'PDF',
                                subtitle: 'Print-ready',
                                icon: Icons.picture_as_pdf_rounded,
                                selected: _format == 'pdf',
                                onTap: () => setState(() => _format = 'pdf'),
                                color: AppColors.error,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _FormatCard(
                                label: 'Excel',
                                subtitle: 'Editable',
                                icon: Icons.table_chart_rounded,
                                selected: _format == 'xlsx',
                                onTap: () => setState(() => _format = 'xlsx'),
                                color: AppColors.riderGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: const BorderSide(color: AppColors.border),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.85)]),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: _submitting ? null : _generate,
                                  icon: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.bolt_rounded, size: 18, color: Colors.white),
                                  label: Text(_submitting ? 'Generating...' : 'Generate Report', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text, IconData icon) => Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: AppColors.deepNavy.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 14, color: AppColors.deepNavy),
          ),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: 0.1)),
        ],
      );

  Color _accentForTemplate(String key) {
    if (key.contains('loan') || key.contains('overdue')) return AppColors.deepNavy;
    if (key.contains('payment')) return AppColors.goldDark;
    if (key.contains('collection')) return AppColors.riderGreen;
    if (key.contains('financial')) return const Color(0xFF6A1B9A);
    if (key.contains('audit')) return const Color(0xFF00838F);
    return AppColors.lenderBlue;
  }
}

class _FormatCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FormatCard({
    required this.label,
    required this.subtitle,
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
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : AppColors.surfaceVariant,
          border: Border.all(color: selected ? color : AppColors.border, width: selected ? 1.6 : 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))] : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? color : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? Colors.transparent : AppColors.border),
              ),
              child: Icon(icon, color: selected ? Colors.white : AppColors.textSecondary, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: selected ? color : AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
                Text(subtitle, style: TextStyle(color: selected ? color.withValues(alpha: 0.7) : AppColors.textTertiary, fontSize: 11)),
              ],
            ),
            const Spacer(),
            if (selected) Icon(Icons.check_circle_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
