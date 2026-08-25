// lib/presentation/features/head_manager/reports/screens/hm_report_history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../providers/hm_report_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class HmReportHistoryScreen extends ConsumerStatefulWidget {
  const HmReportHistoryScreen({super.key});

  @override
  ConsumerState<HmReportHistoryScreen> createState() =>
      _HmReportHistoryScreenState();
}

class _HmReportHistoryScreenState extends ConsumerState<HmReportHistoryScreen> {
  String _selectedType = 'all';
  DateTimeRange? _dateRange;
  String _search = '';

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
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: IconButton(
            onPressed: () => ref.read(hmReportProvider.notifier).loadHistory(),
            icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.textSecondary),
            tooltip: 'Refresh',
          ),
        ),
      ],
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: state.isLoadingHistory
                ? const ShimmerLoader()
                : state.history.isEmpty
                    ? _buildEmptyPremium()
                    : _buildHistoryList(state),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search by template or report name…',
                    hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: Icon(_dateRange == null ? Icons.date_range_rounded : Icons.event_available_rounded, size: 16, color: _dateRange == null ? AppColors.textSecondary : AppColors.deepNavy),
                label: Text(
                  _dateRange == null ? 'Date Range' : '${_dateRange!.start.toDisplay()} – ${_dateRange!.end.toDisplay()}',
                  style: TextStyle(fontSize: 12, color: _dateRange == null ? AppColors.textSecondary : AppColors.deepNavy, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _dateRange == null ? AppColors.border : AppColors.deepNavy.withValues(alpha: 0.3)),
                  backgroundColor: _dateRange == null ? Colors.white : AppColors.deepNavy.withValues(alpha: 0.06),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (_dateRange != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _dateRange = null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.close_rounded, size: 16, color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Filter:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
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
                const SizedBox(width: 8),
                _typeChip('audit', 'Audit'),
                const SizedBox(width: 8),
                _typeChip('ci', 'CI'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String value, String label) {
    final isSelected = _selectedType == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? const LinearGradient(colors: [AppColors.deepNavy, Color(0xFF1A2E4A)]) : null,
          color: isSelected ? null : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.deepNavy : AppColors.border),
          boxShadow: isSelected ? [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.deepNavy)), child: child!),
    );
    if (range != null) setState(() => _dateRange = range);
  }

  Widget _buildHistoryList(HmReportState state) {
    var reports = state.history;
    if (_selectedType != 'all') {
      reports = reports.where((r) => r['template_key']?.toString().contains(_selectedType) ?? false).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      reports = reports.where((r) => (r['template_key']?.toString().toLowerCase().contains(q) ?? false) || (r['report_name']?.toString().toLowerCase().contains(q) ?? false)).toList();
    }
    if (_dateRange != null) {
      reports = reports.where((r) {
        final created = r['created_at'] as String?;
        if (created == null) return false;
        final dt = DateTime.tryParse(created);
        if (dt == null) return false;
        return dt.isAfter(_dateRange!.start) && dt.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }
    if (reports.isEmpty) {
      return const EmptyStateWidget(icon: Icons.filter_list_off_rounded, title: 'No Results', subtitle: 'No reports match your current filters.');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      itemCount: reports.length,
      itemBuilder: (context, i) => Padding(
        padding: EdgeInsets.only(bottom: i == reports.length - 1 ? 0 : 12),
        child: _ReportHistoryCard(report: reports[i]),
      ),
    );
  }

  Widget _buildEmptyPremium() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 80, height: 80, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.deepNavy.withValues(alpha: 0.08), AppColors.gold.withValues(alpha: 0.12)]), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.history_rounded, size: 40, color: AppColors.deepNavy)),
            const SizedBox(height: 18),
            const Text('No Reports Generated', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Generate a report from the Report Library first.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ReportHistoryCard extends StatefulWidget {
  final Map<String, dynamic> report;
  const _ReportHistoryCard({required this.report});

  @override
  State<_ReportHistoryCard> createState() => _ReportHistoryCardState();
}

class _ReportHistoryCardState extends State<_ReportHistoryCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final templateKey = report['template_key'] as String? ?? '';
    final createdAt = report['created_at'] as String?;
    final pdfUrl = report['pdf_url'] as String?;
    final xlsxUrl = report['xlsx_url'] as String?;
    final parameters = report['parameters'] as Map<String, dynamic>? ?? {};
    final color = _colorForKey(templateKey);
    final icon = _iconForKey(templateKey);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _hover ? color.withValues(alpha: 0.25) : AppColors.border),
          boxShadow: _hover
              ? [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))]
              : const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(_labelForKey(templateKey), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text(templateKey.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.4)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(createdAt != null ? DateTime.parse(createdAt).toDisplay() : '–', style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                        if (parameters['date_range'] != null) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.date_range_rounded, size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Text(parameters['date_range'].toString(), style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  _DownloadButton(label: 'PDF', icon: Icons.picture_as_pdf_rounded, color: AppColors.error, hasUrl: pdfUrl != null),
                  const SizedBox(width: 8),
                  _DownloadButton(label: 'Excel', icon: Icons.table_chart_rounded, color: AppColors.riderGreen, hasUrl: xlsxUrl != null),
                ],
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                opacity: _hover ? 1 : 0.5,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForKey(String key) {
    if (key.contains('loan')) return Icons.account_balance_wallet_rounded;
    if (key.contains('payment')) return Icons.payments_rounded;
    if (key.contains('collection')) return Icons.delivery_dining_rounded;
    if (key.contains('borrower') || key.contains('lender')) return Icons.people_rounded;
    if (key.contains('rider')) return Icons.delivery_dining_rounded;
    if (key.contains('financial') || key.contains('revenue')) return Icons.bar_chart_rounded;
    if (key.contains('audit')) return Icons.history_rounded;
    if (key.contains('ci')) return Icons.search_rounded;
    return Icons.description_rounded;
  }

  Color _colorForKey(String key) {
    if (key.contains('loan')) return AppColors.deepNavy;
    if (key.contains('payment')) return AppColors.goldDark;
    if (key.contains('collection')) return AppColors.riderGreen;
    if (key.contains('financial') || key.contains('revenue')) return const Color(0xFF6A1B9A);
    if (key.contains('audit')) return const Color(0xFF00838F);
    if (key.contains('ci')) return AppColors.lenderBlue;
    return AppColors.info;
  }

  String _labelForKey(String key) {
    if (key.isEmpty) return 'Report';
    return key.split('_').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
  }
}

class _DownloadButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool hasUrl;

  const _DownloadButton({required this.label, required this.icon, required this.color, required this.hasUrl});

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.hasUrl;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: enabled
            ? () {
                context.showSnackBarAsToast(SnackBar(
                  content: Text('Opening ${widget.label} report...'),
                  backgroundColor: widget.color,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ));
              }
            : null,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hover && enabled ? widget.color : widget.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: widget.color.withValues(alpha: enabled ? 0.28 : 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: _hover && enabled ? Colors.white : widget.color),
              const SizedBox(width: 6),
              Text(widget.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _hover && enabled ? Colors.white : widget.color)),
            ],
          ),
        ),
      ),
    );
  }
}
