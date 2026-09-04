// lib/presentation/features/head_manager/reports/screens/hm_report_library_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/datasources/remote/report_remote_datasource.dart';
import '../../../../shared/utils/file_downloader.dart';
import '../../../../shared/utils/report_exporter.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class _ReportState {
  final List<Map<String, dynamic>> templates;
  final List<Map<String, dynamic>> history;
  final bool isLoading;
  final bool isGenerating;
  const _ReportState(
      {this.templates = const [],
      this.history = const [],
      this.isLoading = false,
      this.isGenerating = false});
  _ReportState copyWith(
          {List<Map<String, dynamic>>? templates,
          List<Map<String, dynamic>>? history,
          bool? isLoading,
          bool? isGenerating}) =>
      _ReportState(
          templates: templates ?? this.templates,
          history: history ?? this.history,
          isLoading: isLoading ?? this.isLoading,
          isGenerating: isGenerating ?? this.isGenerating);
}

class _ReportNotifier extends StateNotifier<_ReportState>
    with RealtimeRefreshMixin<_ReportState> {
  final ReportRemoteDataSource _ds;
  _ReportNotifier(this._ds) : super(const _ReportState()) {
    bindRealtimeRefresh(['reports'], refresh: () => init(silent: true));
    init();
  }

  Future<void> init({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final templates = await _ds.getReportList();
      final history = await _ds.getRawHistory();
      state = state.copyWith(
        templates: templates,
        history: history,
        isLoading: false,
      );
    } catch (_) {
      if (!silent) state = state.copyWith(isLoading: false);
    }
  }

  Future<Map<String, dynamic>?> generate(
      String templateKey, Map<String, dynamic> params) async {
    state = state.copyWith(isGenerating: true);
    try {
      final res = await _ds.generateReport(
          templateKey: templateKey, parameters: params, format: 'pdf');
      await init();
      state = state.copyWith(isGenerating: false);
      return res;
    } catch (_) {
      state = state.copyWith(isGenerating: false);
      return null;
    }
  }
}

final _reportProvider =
    AutoDisposeStateNotifierProvider<_ReportNotifier, _ReportState>((ref) {
  return _ReportNotifier(sl<ReportRemoteDataSource>());
});

class HmReportLibraryScreen extends ConsumerStatefulWidget {
  const HmReportLibraryScreen({super.key});

  @override
  ConsumerState<HmReportLibraryScreen> createState() =>
      _HmReportLibraryScreenState();
}

class _HmReportLibraryScreenState extends ConsumerState<HmReportLibraryScreen> {
  String _search = '';
  String _selectedCategory = 'all';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_reportProvider);
    return WebScaffold(
      title: 'Reports',
      actions: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: IconButton(
            onPressed: () => ref.read(_reportProvider.notifier).init(),
            icon: const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
            tooltip: 'Refresh',
          ),
        ),
        const SizedBox(width: 12),
      ],
      body: state.isLoading
          ? _buildShimmer()
          : RefreshIndicator(
              onRefresh: () => ref.read(_reportProvider.notifier).init(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchAndFilters(state),
                    const SizedBox(height: 20),
                    _buildSectionTitle(
                      title: 'Report Templates',
                    ),
                    const SizedBox(height: 16),
                    _buildTemplateGrid(context, state),
                    const SizedBox(height: 32),
                    _buildSectionTitle(
                      title: 'Generated Reports History',
                      trailing: state.history.isNotEmpty
                          ? TextButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('View All', style: TextStyle(fontSize: 12)),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    _buildHistory(context, state),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSearchAndFilters(_ReportState state) {
    return Container(
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
                    hintText: 'Search',
                    hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(colors: [AppColors.gold, AppColors.goldDark]),
                ),
                child: ElevatedButton.icon(
                  onPressed: state.isGenerating ? null : () {},
                  icon: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                  label: const Text('New Export', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterPill(
                  label: 'All',
                  selected: _selectedCategory == 'all',
                  onTap: () => setState(() => _selectedCategory = 'all'),
                ),
                _FilterPill(label: 'Loans', selected: _selectedCategory == 'loan', onTap: () => setState(() => _selectedCategory = 'loan')),
                _FilterPill(label: 'Payments', selected: _selectedCategory == 'payment', onTap: () => setState(() => _selectedCategory = 'payment')),
                _FilterPill(label: 'Collections', selected: _selectedCategory == 'collection', onTap: () => setState(() => _selectedCategory = 'collection')),
                _FilterPill(label: 'Financial', selected: _selectedCategory == 'financial', onTap: () => setState(() => _selectedCategory = 'financial')),
                _FilterPill(label: 'Operations', selected: _selectedCategory == 'ops', onTap: () => setState(() => _selectedCategory = 'ops')),
              ].map((w) => Padding(padding: const EdgeInsets.only(right: 8), child: w)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({required String title, Widget? trailing}) => Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ),
          if (trailing != null) trailing,
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: AppColors.divider, height: 1)),
        ],
      );

  Widget _buildTemplateGrid(BuildContext context, _ReportState state) {
    var templates = state.templates.isNotEmpty ? state.templates : _defaultTemplates();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      templates = templates.where((t) => (t['name'] as String? ?? '').toLowerCase().contains(q) || (t['description'] as String? ?? '').toLowerCase().contains(q)).toList();
    }
    if (_selectedCategory != 'all') {
      templates = templates.where((t) => (t['key'] as String? ?? '').contains(_selectedCategory) || (t['name'] as String? ?? '').toLowerCase().contains(_selectedCategory)).toList();
    }
    if (templates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: const Center(child: Text('No templates match your search', style: TextStyle(color: AppColors.textSecondary))),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cross = constraints.maxWidth >= 1100 ? 3 : constraints.maxWidth >= 720 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 98,
          ),
          itemCount: templates.length,
          itemBuilder: (ctx, i) => _Entrance(
            delay: i * 40,
            child: _PremiumTemplateCard(
              data: templates[i],
              generating: state.isGenerating,
              onGenerate: (fmt) => _showGenerateDialog(context, templates[i], initialFormat: fmt),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistory(BuildContext context, _ReportState state) {
    if (state.history.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: const Column(
          children: [
            Text('No reports generated yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            SizedBox(height: 6),
            Text('Choose a template above to create your first export.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        children: state.history.asMap().entries.map((e) {
          final r = e.value;
          final isLast = e.key == state.history.length - 1;
          return Container(
            key: ValueKey(r['id']),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['report_name'] as String? ?? 'Generated Report', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(_formatDate(r['created_at']), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                _HistoryAction(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'PDF',
                  color: AppColors.error,
                  onTap: () => _downloadPdf(context, r['report_name'] as String? ?? 'Report', _normalizeRows(r['data'])),
                ),
                const SizedBox(width: 8),
                _HistoryAction(
                  icon: Icons.table_chart_rounded,
                  label: 'Excel',
                  color: AppColors.riderGreen,
                  onTap: () => _downloadExcel(context, r['report_name'] as String? ?? 'Report', _normalizeRows(r['data'])),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Map<String, dynamic>> _defaultTemplates() => [
        {'key': 'loan_summary', 'name': 'Loan Summary Report', 'description': 'Overview of all loans by status and amount', 'icon': Icons.summarize_rounded, 'has_pdf': true, 'has_excel': true, 'accent': AppColors.deepNavy, 'category': 'Loans'},
        {'key': 'collection_report', 'name': 'Collection Report', 'description': 'Cash and GCash collections summary', 'icon': Icons.delivery_dining_rounded, 'has_pdf': true, 'has_excel': true, 'accent': AppColors.riderGreen, 'category': 'Collections'},
        {'key': 'payment_report', 'name': 'Payment Report', 'description': 'All payments processed in date range', 'icon': Icons.payments_rounded, 'has_pdf': true, 'has_excel': true, 'accent': AppColors.goldDark, 'category': 'Payments'},
        {'key': 'lender_report', 'name': 'Lender Report', 'description': 'All registered lenders and their status', 'icon': Icons.people_rounded, 'has_pdf': true, 'has_excel': true, 'accent': AppColors.lenderBlue, 'category': 'Users'},
        {'key': 'rider_report', 'name': 'Rider Report', 'description': 'Rider performance and assignment history', 'icon': Icons.delivery_dining_rounded, 'has_pdf': true, 'has_excel': true, 'accent': const Color(0xFF4A6572), 'category': 'Operations'},
        {'key': 'employee_report', 'name': 'Employee Report', 'description': 'Employee activity and processing history', 'icon': Icons.badge_rounded, 'has_pdf': true, 'has_excel': true, 'accent': const Color(0xFF5D4037), 'category': 'Users'},
        {'key': 'financial_report', 'name': 'Financial Report', 'description': 'Revenue, interest, and penalty totals', 'icon': LucideIcons.philippinePeso, 'has_pdf': true, 'has_excel': true, 'accent': const Color(0xFF6A1B9A), 'category': 'Financial'},
        {'key': 'overdue_report', 'name': 'Overdue Loans Report', 'description': 'Loans with delayed payments', 'icon': Icons.warning_rounded, 'has_pdf': true, 'has_excel': true, 'accent': AppColors.error, 'category': 'Loans'},
        {'key': 'audit_report', 'name': 'Audit Report', 'description': 'System activity and audit trail', 'icon': Icons.history_rounded, 'has_pdf': true, 'has_excel': true, 'accent': const Color(0xFF00838F), 'category': 'Operations'},
        {'key': 'ci_report', 'name': 'CI Report', 'description': 'Credit investigation assignments and outcomes', 'icon': Icons.search_rounded, 'has_pdf': true, 'has_excel': true, 'accent': AppColors.lenderBlueDark, 'category': 'Operations'},
        {'key': 'account_upgrade_report', 'name': 'Account Upgrade Report', 'description': 'Account upgrade submission and verification status', 'icon': Icons.verified_user_rounded, 'has_pdf': true, 'has_excel': true, 'accent': AppColors.riderGreenDark, 'category': 'Users'},
        {'key': 'disbursement_report', 'name': 'Disbursement Report', 'description': 'Loan disbursements by method and amount', 'icon': Icons.account_balance_rounded, 'has_pdf': true, 'has_excel': true, 'accent': AppColors.navyLight, 'category': 'Financial'},
      ];

  Future<void> _showGenerateDialog(BuildContext context, Map<String, dynamic> template, {String initialFormat = 'pdf'}) async {
    DateTimeRange? range;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Generate: ${template['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10)),
                  child: Text(template['description'] as String? ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                const SizedBox(height: 16),
                const Text('Date Range', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDateRangePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (picked != null) setS(() => range = picked);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range_rounded, size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 10),
                        Text(range == null ? 'Select Date Range' : '${DateFormat('MMM dd').format(range!.start)} – ${DateFormat('MMM dd, yyyy').format(range!.end)}', style: TextStyle(color: range == null ? AppColors.textTertiary : AppColors.textPrimary, fontSize: 13, fontWeight: range == null ? FontWeight.w400 : FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: range == null
                  ? null
                  : () async {
                      final selected = range!;
                      debugPrint('[DEBUG] Proceed tapped template=${template['name']} range=$selected format=$initialFormat');
                      Navigator.pop(ctx);
                      await Future.delayed(const Duration(milliseconds: 250));
                      if (!context.mounted) return;
                      try {
                        final result = await ref.read(_reportProvider.notifier).generate(template['key'] as String, {
                          'date_from': DateFormat('yyyy-MM-dd').format(selected.start),
                          'date_to': DateFormat('yyyy-MM-dd').format(selected.end),
                        });
                        if (!context.mounted) return;
                        dynamic rawData;
                        if (result != null) {
                          rawData = result['data'] ?? result['rows'] ?? result['records'] ?? result;
                          if (rawData is Map && rawData.containsKey('data')) rawData = rawData['data'];
                        }
                        debugPrint('[DEBUG] Generate result rawData: $rawData');
                        final dataForPreview = rawData ?? [];
                        await _showDownloadDialog(context, template['name'] as String? ?? 'Report', dataForPreview, dateRange: selected, initialFormat: initialFormat);
                      } catch (e) {
                        debugPrint('[DEBUG] Generate error: $e');
                        if (!context.mounted) return;
                        await _showDownloadDialog(context, template['name'] as String? ?? 'Report', [], dateRange: selected, initialFormat: initialFormat);
                      }
                    },
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Proceed'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.deepNavy, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDownloadDialog(BuildContext context, String title, dynamic data, {DateTimeRange? dateRange, String? initialFormat}) async {
    final rows = _normalizeRows(data);
    final columns = _columnsOf(rows);
    debugPrint('Preview rows: ${rows.length} columns: $columns firstRow: ${rows.isNotEmpty ? rows.first : 'empty'}');
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 680),
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.divider)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.description_rounded, color: AppColors.success, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                            Text(
                              dateRange == null
                                  ? '${rows.length} record${rows.length == 1 ? '' : 's'} • Template preview'
                                  : '${DateFormat('MMM dd, yyyy').format(dateRange.start)} – ${DateFormat('MMM dd, yyyy').format(dateRange.end)} • Template preview',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                // Preview table - Template
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Template header inside preview
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                            child: Column(
                              children: [
                                const Text('Jireta Loans & Credit Corp', style: TextStyle(fontSize: 10, color: AppColors.textSecondary, letterSpacing: 0.4)),
                                const SizedBox(height: 4),
                                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary), textAlign: TextAlign.center),
                                if (dateRange != null) ...[
                                  const SizedBox(height: 4),
                                  Text('${DateFormat('MMM dd, yyyy').format(dateRange.start)} – ${DateFormat('MMM dd, yyyy').format(dateRange.end)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: initialFormat == 'xlsx' ? AppColors.riderGreen.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: initialFormat == 'xlsx' ? AppColors.riderGreen.withValues(alpha: 0.18) : AppColors.error.withValues(alpha: 0.18)),
                                ),
                                child: Text(initialFormat == 'xlsx' ? 'Excel Layout' : 'PDF Layout', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: initialFormat == 'xlsx' ? AppColors.riderGreen : AppColors.error, letterSpacing: 0.4)),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(initialFormat == 'xlsx' ? AppColors.riderGreen : AppColors.deepNavy),
                                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                                  dataRowMinHeight: 32,
                                  dataRowMaxHeight: 36,
                                  headingRowHeight: 36,
                                  columnSpacing: 16,
                                  horizontalMargin: 12,
                                  border: TableBorder.all(color: AppColors.border, width: 0.6),
                                  columns: [for (final c in columns) DataColumn(label: Text(c, style: const TextStyle(fontSize: 11)))],
                                  rows: rows.isEmpty
                                      ? [
                                          DataRow(cells: [for (final _ in columns) const DataCell(Text('—', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)))]),
                                        ]
                                      : [
                                          for (final r in rows.take(200))
                                            DataRow(cells: [for (final c in columns) DataCell(Text(r[c]?.toString() ?? '', style: const TextStyle(fontSize: 11)))]),
                                        ],
                                ),
                              ),
                            ],
                          ),
                          if (rows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text('No records for selected period — template preview', style: TextStyle(fontSize: 11, color: AppColors.textSecondary), textAlign: TextAlign.center),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (rows.length > 200)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: AppColors.surfaceVariant,
                    child: Text('Showing first 200 of ${rows.length} records. Download to see all.', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), textAlign: TextAlign.center),
                  ),
                // Actions
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
                  child: Row(
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            final bytes = await buildPdf(title: title, rows: rows);
                            await Printing.layoutPdf(onLayout: (_) async => bytes);
                          } catch (_) {
                            if (ctx.mounted) ctx.showSnackBarAsToast(const SnackBar(content: Text('Print failed'), backgroundColor: AppColors.error));
                          }
                        },
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Print'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          await _downloadExcel(context, title, rows);
                        },
                        icon: const Icon(Icons.table_chart_rounded, color: AppColors.riderGreen, size: 16),
                        label: const Text('Excel', style: TextStyle(color: AppColors.riderGreen)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          await _downloadPdf(context, title, rows);
                        },
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                        label: const Text('Download PDF'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> _columnsOf(List<Map<String, dynamic>> rows) {
    final cols = <String>[];
    for (final r in rows) {
      for (final k in r.keys) {
        if (!cols.contains(k)) cols.add(k);
      }
    }
    if (cols.isEmpty) cols.add('No Data');
    return cols;
  }

  Future<void> _downloadPdf(BuildContext context, String title, List<Map<String, dynamic>> rows) async {
    try {
      final bytes = await buildPdf(title: title, rows: rows);
      await saveFile(bytes, '${sanitizeFileName(title)}.pdf');
      if (context.mounted) _notifyDownload(context, title, 'PDF');
    } catch (e) {
      if (context.mounted) _notifyError(context);
    }
  }

  Future<void> _downloadExcel(BuildContext context, String title, List<Map<String, dynamic>> rows) async {
    try {
      final bytes = buildXlsx(rows);
      await saveFile(bytes, '${sanitizeFileName(title)}.xlsx');
      if (context.mounted) _notifyDownload(context, title, 'Excel');
    } catch (e) {
      if (context.mounted) _notifyError(context);
    }
  }

  void _notifyDownload(BuildContext context, String title, String format) {
    if (!context.mounted) return;
    context.showSnackBarAsToast(SnackBar(content: Text('$title downloaded as $format'), backgroundColor: AppColors.success));
  }

  void _notifyError(BuildContext context) {
    if (!context.mounted) return;
    context.showSnackBarAsToast(const SnackBar(content: Text('Failed to download report'), backgroundColor: AppColors.error));
  }

  List<Map<String, dynamic>> _normalizeRows(dynamic data) {
    List<dynamic>? list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      final inner = data['data'] ?? data['rows'] ?? data['records'] ?? data['items'];
      if (inner is List) {
        list = inner;
      } else if (inner is Map && inner['data'] is List) {
        list = inner['data'] as List;
      } else if (!data.containsKey('data')) {
        // Single row map case — wrap it
        list = [data];
      }
    }
    if (list == null) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is Map) {
        out.add(item.map((k, v) => MapEntry(k.toString(), _flatten(v))));
      }
    }
    return out;
  }

  dynamic _flatten(dynamic v) {
    if (v is List) {
      return v.map((e) => e is Map ? e.values.join(' / ') : e.toString()).join('; ');
    }
    if (v is Map) return v.values.join(' / ');
    return v;
  }

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    try {
      // PostgREST returns UTC instants — convert to Manila time (UTC+8)
      // before formatting so timestamps match the system clock.
      return DateFormat('MMM dd, yyyy hh:mm a')
          .format(toManila(DateTime.parse(d.toString())));
    } catch (_) {
      return d.toString();
    }
  }



  Widget _buildShimmer() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(height: 180, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 16, mainAxisSpacing: 16, mainAxisExtent: 98),
              itemCount: 6,
              itemBuilder: (_, __) => const ShimmerLoader(height: 98),
            ),
          ],
        ),
      );
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.deepNavy : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.deepNavy : AppColors.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}

class _PremiumTemplateCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool generating;
  final void Function(String format) onGenerate;
  const _PremiumTemplateCard({required this.data, required this.generating, required this.onGenerate});
  @override
  State<_PremiumTemplateCard> createState() => _PremiumTemplateCardState();
}

class _PremiumTemplateCardState extends State<_PremiumTemplateCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final accent = widget.data['accent'] as Color? ?? AppColors.deepNavy;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hover ? accent.withValues(alpha: 0.35) : AppColors.border),
          boxShadow: _hover
              ? [BoxShadow(color: accent.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 8))]
              : const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 4, color: accent),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(builder: (_) {
                      final raw = widget.data['name'] as String? ?? '';
                      final display = raw.replaceAll(RegExp(r'\s*Report\s*', caseSensitive: false), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
                      return Text(display.isEmpty ? raw : display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary));
                    }),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Spacer(),
                        GestureDetector(
                          onTap: widget.generating ? null : () => widget.onGenerate('pdf'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.error.withValues(alpha: 0.18))),
                            child: const Text('PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.error)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: widget.generating ? null : () => widget.onGenerate('xlsx'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: AppColors.riderGreen.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.riderGreen.withValues(alpha: 0.18))),
                            child: const Text('Excel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.riderGreen)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _HistoryAction({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.18))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color))]),
      ),
    );
  }
}

class _Entrance extends StatefulWidget {
  final Widget child;
  final int delay;
  const _Entrance({required this.child, this.delay = 0});
  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _offset = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: widget.delay), () => mounted ? _ctrl.forward() : null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: SlideTransition(position: _offset, child: widget.child));
}
