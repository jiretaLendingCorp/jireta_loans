// lib/presentation/features/head_manager/reports/screens/hm_report_history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../providers/hm_report_provider.dart';

class HmReportHistoryScreen extends ConsumerStatefulWidget {
  const HmReportHistoryScreen({super.key});

  @override
  ConsumerState<HmReportHistoryScreen> createState() =>
      _HmReportHistoryScreenState();
}

class _HmReportHistoryScreenState extends ConsumerState<HmReportHistoryScreen> {
  String _selectedType = 'all';
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(hmReportProvider.notifier).loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmReportProvider);

    return WebScaffold(
      title: 'Report History',
      actions: [
        IconButton(
          onPressed: () => ref.read(hmReportProvider.notifier).loadHistory(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          tooltip: 'Refresh',
        ),
      ],
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: state.isLoadingHistory
                ? const ShimmerLoader()
                : state.history.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.history,
                        title: 'No Reports Generated',
                        subtitle:
                            'Generate a report from the Report Library first.',
                      )
                    : _buildHistoryList(state),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text(
              'Filter:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            _typeChip('all', 'All Reports'),
            const SizedBox(width: 8),
            _typeChip('loan', 'Loan'),
            const SizedBox(width: 8),
            _typeChip('payment', 'Payment'),
            const SizedBox(width: 8),
            _typeChip('collection', 'Collection'),
            const SizedBox(width: 8),
            _typeChip('financial', 'Financial'),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range, size: 16),
              label: Text(
                _dateRange == null
                    ? 'Date Range'
                    : '${_dateRange!.start.toDisplay()} – ${_dateRange!.end.toDisplay()}',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            if (_dateRange != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() => _dateRange = null),
                icon: const Icon(Icons.clear, size: 16),
                tooltip: 'Clear date filter',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String value, String label) {
    final isSelected = _selectedType == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.deepNavy : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.deepNavy),
        ),
        child: child!,
      ),
    );
    if (range != null) setState(() => _dateRange = range);
  }

  Widget _buildHistoryList(HmReportState state) {
    var reports = state.history;

    if (_selectedType != 'all') {
      reports = reports
          .where((r) =>
              r['template_key']?.toString().contains(_selectedType) ?? false)
          .toList();
    }

    if (_dateRange != null) {
      reports = reports.where((r) {
        final created = r['created_at'] as String?;
        if (created == null) return false;
        final dt = DateTime.tryParse(created);
        if (dt == null) return false;
        return dt.isAfter(_dateRange!.start) &&
            dt.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    if (reports.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.filter_list_off,
        title: 'No Results',
        subtitle: 'No reports match your current filters.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: reports.length,
      itemBuilder: (context, i) =>
          _ReportHistoryCard(key: ValueKey(reports[i]['id']), report: reports[i]),
    );
  }
}

class _ReportHistoryCard extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ReportHistoryCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final templateKey = report['template_key'] as String? ?? '';
    final createdAt = report['created_at'] as String?;
    final pdfUrl = report['pdf_url'] as String?;
    final xlsxUrl = report['xlsx_url'] as String?;
    final parameters = report['parameters'] as Map<String, dynamic>? ?? {};

    IconData icon = _iconForKey(templateKey);
    Color color = _colorForKey(templateKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _labelForKey(templateKey),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 12,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        createdAt != null
                            ? DateTime.parse(createdAt).toDisplay()
                            : '–',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      if (parameters['date_range'] != null) ...[
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.date_range,
                          size: 12,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          parameters['date_range'].toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Row(
              children: [
                if (pdfUrl != null)
                  _DownloadButton(
                    label: 'PDF',
                    icon: Icons.picture_as_pdf,
                    color: AppColors.error,
                    url: pdfUrl,
                  ),
                if (xlsxUrl != null) ...[
                  const SizedBox(width: 8),
                  _DownloadButton(
                    label: 'Excel',
                    icon: Icons.table_chart,
                    color: AppColors.success,
                    url: xlsxUrl,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForKey(String key) {
    if (key.contains('loan')) return Icons.account_balance_wallet;
    if (key.contains('payment')) return Icons.payments;
    if (key.contains('collection')) return Icons.local_shipping;
    if (key.contains('borrower') || key.contains('lender')) return Icons.people;
    if (key.contains('rider')) return Icons.delivery_dining;
    if (key.contains('financial') || key.contains('revenue')) {
      return Icons.bar_chart;
    }
    if (key.contains('audit')) return Icons.history;
    if (key.contains('ci')) return Icons.search;
    return Icons.description;
  }

  Color _colorForKey(String key) {
    if (key.contains('loan')) return AppColors.deepNavy;
    if (key.contains('payment')) return AppColors.gold;
    if (key.contains('collection')) return AppColors.riderGreen;
    if (key.contains('financial') || key.contains('revenue')) {
      return const Color(0xFF6A1B9A);
    }
    return AppColors.info;
  }

  String _labelForKey(String key) {
    return key
        .split('_')
        .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }
}

class _DownloadButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String url;

  const _DownloadButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opening $label report...'),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
      icon: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
