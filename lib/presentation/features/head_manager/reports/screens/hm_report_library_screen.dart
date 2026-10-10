// lib/presentation/features/head_manager/reports/screens/hm_report_library_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/datasources/remote/report_remote_datasource.dart';
import '../../../../shared/utils/file_downloader.dart';
import '../../../../shared/utils/report_exporter.dart';
import '../../../../shared/widgets/pdf_zoom_viewer.dart';
import '../../../../shared/widgets/forms/app_date_range_picker.dart';
import '../../../../shared/widgets/filter_dropdown.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';
import '../widgets/loan_records_preview.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

/// Inaayos ang iba-ibang hugis ng sagot ng `reports-generate` (List, `data`,
/// `rows`, `records`, `items`) sa isang listahan ng row maps.
List<Map<String, dynamic>> _normalizeRows(dynamic data) {
  List<dynamic>? list;
  if (data is List) {
    list = data;
  } else if (data is Map) {
    final inner =
        data['data'] ?? data['rows'] ?? data['records'] ?? data['items'];
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
    if (item is Map) out.add(item.map((k, v) => MapEntry(k.toString(), _flatten(v))));
  }
  return out;
}

dynamic _flatten(dynamic v) {
  if (v is List) {
    return v
        .map((e) => e is Map ? e.values.join(' / ') : e.toString())
        .join('; ');
  }
  if (v is Map) return v.values.join(' / ');
  return v;
}

class _ReportState {
  final List<Map<String, dynamic>> templates;
  final List<Map<String, dynamic>> history;

  /// Mga loan record ng Interest Report para sa Loan Report section ng
  /// Reports page (Amount / Interest / Total ang columns).
  final List<Map<String, dynamic>> records;
  final bool isLoading;
  final bool isLoadingRecords;
  final bool isGenerating;
  const _ReportState(
      {this.templates = const [],
      this.history = const [],
      this.records = const [],
      this.isLoading = false,
      this.isLoadingRecords = false,
      this.isGenerating = false});
  _ReportState copyWith(
          {List<Map<String, dynamic>>? templates,
          List<Map<String, dynamic>>? history,
          List<Map<String, dynamic>>? records,
          bool? isLoading,
          bool? isLoadingRecords,
          bool? isGenerating}) =>
      _ReportState(
          templates: templates ?? this.templates,
          history: history ?? this.history,
          records: records ?? this.records,
          isLoading: isLoading ?? this.isLoading,
          isLoadingRecords: isLoadingRecords ?? this.isLoadingRecords,
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

  /// Kinukuha ang loan records ng Interest Report para sa Loan Report section
  /// ng Reports page. Preview lang ito (`preview: true`) — hindi ito nagdadagdag
  /// ng entry sa Generated Reports History.
  Future<void> loadLoanRecords(DateTimeRange range,
      {String templateKey = kInterestReportKey}) async {
    state = state.copyWith(isLoadingRecords: true);
    try {
      final res = await _ds.generateReport(
        templateKey: templateKey,
        parameters: {
          'date_from': DateFormat('yyyy-MM-dd').format(range.start),
          'date_to': DateFormat('yyyy-MM-dd').format(range.end),
        },
        format: 'pdf',
        preview: true,
      );
      final raw = res['data'] ?? res['rows'] ?? res['records'] ?? res;
      state = state.copyWith(
        records: _normalizeRows(raw),
        isLoadingRecords: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingRecords: false);
    }
  }

  /// Refreshes ONLY the history preview — never re-fetches templates or flips
  /// the full-screen loading state while the generate/download flow is open.
  Future<void> _refreshHistorySilently() async {
    try {
      final history = await _ds.getRawHistory();
      state = state.copyWith(history: history);
    } catch (_) {
      // Non-fatal: keep the last known history until the next real load.
    }
  }

  /// [preview] = true para sa Proceed ng date-range modal — kukunin lang ang
  /// rows at hindi ito naka-record sa `reports`. Sa Excel/PDF export
  /// (preview = false) lang nagkakaroon ng bagong Generated Reports History entry.
  Future<Map<String, dynamic>?> generate(
      String templateKey, Map<String, dynamic> params,
      {bool preview = false, String format = 'pdf'}) async {
    state = state.copyWith(isGenerating: true);
    try {
      final res = await _ds.generateReport(
          templateKey: templateKey,
          parameters: params,
          format: format,
          preview: preview);
      // Bagong history entry lang ang ire-refresh kapag export — sa preview,
      // wala namang naidagdag kaya hindi na kailangan.
      if (!preview) await _refreshHistorySilently();
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

/// Mga report na kayang ipakita ng Loan Records section — Amount / Interest /
/// Total lang ang columns nila (hugis ng `interest_report` rows).
const List<({String label, String key})> _loanRecordTypes = [
  (label: 'Loan Records', key: kInterestReportKey),
];

class _HmReportLibraryScreenState extends ConsumerState<HmReportLibraryScreen> {
  /// 5 reports lang kada page ng Generated Reports History.
  static const int _historyPageSize = 5;
  int _historyPage = 1;

  /// Nakatago (HINDI tinanggal) ang "Report Templates" section — ang Loan
  /// Records section na ang nasa itaas. Gawing `true` para ibalik ito.
  static const bool _showTemplateSection = false;

  /// Panahon ng Loan Report section — default ay ang buong kasalukuyang buwan
  /// (Manila), tulad ng "Sep 01 – Sep 30" pill ng mockup.
  late DateTimeRange _range = _monthRange(nowManila());

  /// Naka-filter na loan records mula sa Loan Report section — ito ang
  /// ida-download ng Export button (tugma sa nakikita sa screen).
  List<Map<String, dynamic>> _exportRows = const [];

  /// Napiling Report Type sa Loan Records section.
  String _reportType = kInterestReportKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        ref.read(_reportProvider.notifier).loadLoanRecords(_range, templateKey: _reportType));
  }

  static DateTimeRange _monthRange(DateTime now) =>
      DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);

  Future<void> _pickRange() async {
    final range = await showAppDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: nowManila(),
      initialDateRange: _range,
    );
    if (range == null) return;
    setState(() => _range = range);
    await ref.read(_reportProvider.notifier).loadLoanRecords(range);
  }

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
            onPressed: () {
              ref.read(_reportProvider.notifier).init();
              ref.read(_reportProvider.notifier).loadLoanRecords(_range);
            },
            icon: const Icon(Icons.refresh,
                size: 20, color: AppColors.textSecondary),
            tooltip: 'Refresh',
          ),
        ),
        const SizedBox(width: 12),
      ],
      body: state.isLoading
          ? _buildShimmer()
          : RefreshIndicator(
              onRefresh: () {
                ref.read(_reportProvider.notifier).loadLoanRecords(_range);
                return ref.read(_reportProvider.notifier).init();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Loan Report section — filter card, summary cards, at
                    // "Loan Records" table na may footer (mockup layout).
                    _buildLoanReport(context, state),
                    // Nakatago ang Report Templates section (nasa `
                    // _showTemplateSection` ang switch) — nandiyan pa rin ang
                    // code at table, hindi lang ipinapakita.
                    if (_showTemplateSection) ...[
                      const SizedBox(height: 32),
                      _buildSectionTitle(
                        title: 'Report Templates',
                      ),
                      const SizedBox(height: 16),
                      _buildTemplateTable(context, state),
                    ],
                    const SizedBox(height: 32),
                    _buildSectionTitle(
                      title: 'Generated Reports History',
                    ),
                    const SizedBox(height: 16),
                    _buildHistory(context, state),
                  ],
                ),
              ),
            ),
    );
  }

  /// Loan Report section ng Reports page — Amount / Interest / Total lang ang
  /// columns ng mga loan record, at ang Export button ay ang mga nakalabas na
  /// (naka-filter) na rows ang ida-download.
  Widget _buildLoanReport(BuildContext context, _ReportState state) {
    if (state.isLoadingRecords && state.records.isEmpty) {
      return const Column(
        children: [
          ShimmerLoader(height: 96),
          SizedBox(height: 16),
          ShimmerLoader(height: 110),
          SizedBox(height: 16),
          ShimmerLoader(height: 320),
        ],
      );
    }
    return LoanRecordsPreview(
      rows: state.records,
      dateRange: _range,
      onPickDateRange: _pickRange,
      exportActions: _buildExportButton(context),
      leadingFilters: [_buildReportTypeFilter()],
      onFilteredChanged: (rows) => _exportRows = rows,
    );
  }

  /// "Report Type" dropdown ng Loan Records section — ang napiling type ang
  /// pinapasa sa `reports-generate`. Isa pa lang ang suportadong type (Amount /
  /// Interest / Total ang columns nito); idagdag lang dito ang bago kapag may
  /// parehong hugis ng rows.
  Widget _buildReportTypeFilter() => labeledFilterField(
        'Report Type',
        FilterDropdown<String>(
          value: _reportType,
          items: [
            for (final t in _loanRecordTypes)
              DropdownMenuItem(value: t.key, child: Text(t.label)),
          ],
          onChanged: (v) {
            if (v == null || v == _reportType) return;
            setState(() => _reportType = v);
            ref.read(_reportProvider.notifier).loadLoanRecords(_range, templateKey: v);
          },
        ),
      );

  /// "Export" button (PDF o Excel) — kapareho ng mockup na nasa may filter row.
  Widget _buildExportButton(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Export loan records',
        onSelected: (format) => _exportLoanRecords(context, format),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        itemBuilder: (ctx) => const [
          PopupMenuItem(
              value: 'pdf',
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf_rounded,
                      size: 16, color: AppColors.error),
                  SizedBox(width: 8),
                  Text('Export PDF'),
                ],
              )),
          PopupMenuItem(
              value: 'xlsx',
              child: Row(
                children: [
                  Icon(Icons.table_chart_rounded,
                      size: 16, color: AppColors.riderGreen),
                  SizedBox(width: 8),
                  Text('Export Excel'),
                ],
              )),
        ],
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.deepNavy,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_rounded, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Text('Export',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Colors.white),
            ],
          ),
        ),
      );

  /// Ida-download ang naka-filter na loan records at ire-record sa Generated
  /// Reports History (tulad ng Excel/PDF export sa preview modal).
  Future<void> _exportLoanRecords(BuildContext context, String format) async {
    const title = 'Interest Report';
    final params = <String, dynamic>{
      'date_from': DateFormat('yyyy-MM-dd').format(_range.start),
      'date_to': DateFormat('yyyy-MM-dd').format(_range.end),
    };
    final saved =
        await _recordExport(kInterestReportKey, params, format: format);
    if (!context.mounted) return;
    if (!saved) _notifyExportNotRecorded(context);
    if (format == 'xlsx') {
      await _downloadExcel(context, title, _exportRows);
    } else {
      await _downloadPdf(context, title, _exportRows);
    }
  }

  Widget _buildSectionTitle({required String title, Widget? trailing}) => Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ),
          if (trailing != null) trailing,
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: AppColors.divider, height: 1)),
        ],
      );

  /// Talaan ng lahat ng report templates — pangalan at maikling paliwanag,
  /// kategorya, mga available na format, at Generate action sa huling column.
  Widget _buildTemplateTable(BuildContext context, _ReportState state) {
    final templates =
        state.templates.isNotEmpty ? state.templates : _defaultTemplates();
    if (templates.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border)),
        child: const Center(
            child: Text('No report templates available',
                style: TextStyle(color: AppColors.textSecondary))),
      );
    }
    return ResponsiveListCard(
      minTableWidth: 780,
      variant: ResponsiveListVariant.premium,
      columns: const [
        ResponsiveCol('Report', icon: Icons.description_outlined, flex: 4),
        ResponsiveCol('Category', icon: Icons.sell_outlined, flex: 2),
        ResponsiveCol('Formats', icon: Icons.file_download_outlined, flex: 2),
      ],
      actionsCol: const ResponsiveActionsCol(
        label: 'Action',
        icon: Icons.bolt_outlined,
        width: 132,
        alignEnd: true,
      ),
      rows: [
        for (final t in templates)
          _templateRow(context, t, generating: state.isGenerating),
      ],
    );
  }

  /// Isang row ng Report Templates table.
  ResponsiveRow _templateRow(BuildContext context, Map<String, dynamic> t,
      {required bool generating}) {
    final meta = _metaForKey(t['key'] as String? ?? '');
    final accent = meta['accent'] as Color? ?? AppColors.deepNavy;
    final icon = meta['icon'] as IconData? ?? Icons.description_rounded;
    final name = _displayName(
        t['name'] as String? ?? meta['name'] as String? ?? 'Report');
    final description =
        t['description'] as String? ?? meta['description'] as String? ?? '';
    final category =
        t['category'] as String? ?? meta['category'] as String? ?? 'General';
    final hasPdf = t['has_pdf'] as bool? ?? meta['has_pdf'] as bool? ?? true;
    final hasExcel = t['has_excel'] as bool? ?? meta['has_excel'] as bool? ?? true;

    return ResponsiveRow(
      cells: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.textPrimary)),
                  if (description.isNotEmpty)
                    Text(description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.20)),
            ),
            child: Text(category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (hasPdf)
                const _FormatChip(label: 'PDF', color: AppColors.error),
              if (hasExcel)
                const _FormatChip(label: 'XLSX', color: AppColors.riderGreen),
              if (!hasPdf && !hasExcel)
                const Text('—',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textTertiary)),
            ],
          ),
        ),
      ],
      actions: _GenerateButton(
        accent: accent,
        enabled: !generating,
        onTap: () => _showGenerateDialog(context, t),
      ),
    );
  }

  /// Icon at accent color ng isang template key — hango sa `_defaultTemplates()`.
  Map<String, dynamic> _metaForKey(String key) {
    for (final t in _defaultTemplates()) {
      if (t['key'] == key) return t;
    }
    return const <String, dynamic>{};
  }

  /// Maikling pangalan sa table — tinatanggal ang "Report" na suffix.
  String _displayName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'\s*Report\s*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? raw : cleaned;
  }

  Widget _buildHistory(BuildContext context, _ReportState state) {
    if (state.history.isEmpty) {
      return Container(
        // Full width — kung hindi, nag-shrink-wrap lang ito sa haba ng text
        // dahil `CrossAxisAlignment.start` ang parent Column.
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border)),
        child: const Column(
          children: [
            Text('No reports generated yet',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            SizedBox(height: 6),
            Text('Choose a template above to create your first export.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    // Client-side pagination — 5 reports kada page.
    final total = state.history.length;
    final totalPages = (total / _historyPageSize).ceil();
    final page = _historyPage > totalPages ? totalPages : _historyPage;
    final pageItems = state.history
        .skip((page - 1) * _historyPageSize)
        .take(_historyPageSize)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveListCard(
          minTableWidth: 780,
          variant: ResponsiveListVariant.premium,
          columns: const [
            ResponsiveCol('Report', icon: Icons.description_outlined, flex: 4),
            ResponsiveCol('Format',
                icon: Icons.file_download_outlined, flex: 1),
            ResponsiveCol('Generated By', icon: Icons.person_outline, flex: 2),
            ResponsiveCol('Date', icon: Icons.schedule_outlined, flex: 2),
          ],
          rows: [
            for (final r in pageItems) _historyTableRow(r),
          ],
        ),
        if (totalPages > 1) ...[
          const SizedBox(height: 12),
          _buildHistoryPagination(page, totalPages, total),
        ],
      ],
    );
  }

  /// Isang row ng Generated Reports History.
  ResponsiveRow _historyTableRow(Map<String, dynamic> r) {
    final isExcel =
        (r['format'] as String? ?? 'pdf').toLowerCase().contains('xls');
    return ResponsiveRow(
      cells: [
        Text(r['report_name'] as String? ?? 'Generated Report',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Align(
          alignment: Alignment.centerLeft,
          child: _FormatChip(
            label: isExcel ? 'XLSX' : 'PDF',
            color: isExcel ? AppColors.riderGreen : AppColors.error,
          ),
        ),
        Text(_generatedBy(r['generated_by']),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.textSecondary)),
        Text(_formatDate(r['created_at']),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.textSecondary)),
      ],
    );
  }

  /// Pangalan ng nag-generate — sumasalo sa `generated_by` na String o map.
  String _generatedBy(dynamic v) {
    if (v == null) return '—';
    if (v is Map) {
      final name = [v['first_name'], v['last_name']]
          .whereType<Object>()
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .join(' ');
      return name.isEmpty ? '—' : name;
    }
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  /// Prev / page counter / Next sa ilalim ng history table.
  Widget _buildHistoryPagination(int page, int totalPages, int total) {
    final from = (page - 1) * _historyPageSize + 1;
    final rawTo = page * _historyPageSize;
    final to = rawTo > total ? total : rawTo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text('Showing $from–$to of $total',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const Spacer(),
          _PageBtn(
            icon: Icons.chevron_left_rounded,
            enabled: page > 1,
            onTap: () => setState(() => _historyPage = page - 1),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: AppColors.deepNavy,
                borderRadius: BorderRadius.circular(20)),
            child: Text('$page / $totalPages',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
          const SizedBox(width: 8),
          _PageBtn(
            icon: Icons.chevron_right_rounded,
            enabled: page < totalPages,
            onTap: () => setState(() => _historyPage = page + 1),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _defaultTemplates() => [
        {
          'key': 'loan_summary',
          'name': 'Loan Summary Report',
          'description': 'Overview of all loans by status and amount',
          'icon': Icons.summarize_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': AppColors.deepNavy,
          'category': 'Loans'
        },
        {
          'key': 'collection_report',
          'name': 'Collection Report',
          'description': 'Cash and GCash collections summary',
          'icon': Icons.delivery_dining_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': AppColors.riderGreen,
          'category': 'Collections'
        },
        {
          'key': 'payment_report',
          'name': 'Payment Report',
          'description': 'All payments processed in date range',
          'icon': Icons.payments_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': AppColors.goldDark,
          'category': 'Payments'
        },
        {
          'key': 'lender_report',
          'name': 'Lender Report',
          'description': 'All registered lenders and their status',
          'icon': Icons.people_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': AppColors.lenderBlue,
          'category': 'Users'
        },
        {
          'key': 'rider_report',
          'name': 'Rider Report',
          'description': 'Rider performance and assignment history',
          'icon': Icons.delivery_dining_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': const Color(0xFF4A6572),
          'category': 'Operations'
        },
        {
          'key': 'employee_report',
          'name': 'Employee Report',
          'description': 'Employee activity and processing history',
          'icon': Icons.badge_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': const Color(0xFF5D4037),
          'category': 'Users'
        },
        {
          'key': 'financial_report',
          'name': 'Financial Report',
          'description': 'Revenue, interest, and penalty totals',
          'icon': LucideIcons.philippinePeso,
          'has_pdf': true,
          'has_excel': true,
          'accent': const Color(0xFF6A1B9A),
          'category': 'Financial'
        },
        {
          'key': 'revenue_report',
          'name': 'Revenue Report',
          'description': 'Monthly and cumulative revenue analysis',
          'icon': Icons.trending_up_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': const Color(0xFF00897B),
          'category': 'Financial'
        },
        {
          'key': 'interest_report',
          'name': 'Interest Report',
          'description': 'Interest earned per loan and period',
          'icon': Icons.percent_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': const Color(0xFF3949AB),
          'category': 'Financial'
        },
        {
          'key': 'penalty_report',
          'name': 'Penalty Report',
          'description': 'Applied penalties with loan and lender details',
          'icon': Icons.gavel_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': const Color(0xFFC62828),
          'category': 'Financial'
        },
        {
          'key': 'overdue_report',
          'name': 'Overdue Loans Report',
          'description': 'Loans with delayed payments',
          'icon': Icons.warning_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': AppColors.error,
          'category': 'Loans'
        },
        {
          'key': 'audit_report',
          'name': 'Audit Report',
          'description': 'System activity and audit trail',
          'icon': Icons.history_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': const Color(0xFF00838F),
          'category': 'Operations'
        },
        {
          'key': 'ci_report',
          'name': 'CI Report',
          'description': 'Credit investigation assignments and outcomes',
          'icon': Icons.search_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': AppColors.lenderBlueDark,
          'category': 'Operations'
        },
        {
          'key': 'account_upgrade_report',
          'name': 'Account Upgrade Report',
          'description': 'Account upgrade submission and verification status',
          'icon': Icons.verified_user_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': AppColors.riderGreenDark,
          'category': 'Users'
        },
        {
          'key': 'disbursement_report',
          'name': 'Disbursement Report',
          'description': 'Loan disbursements by method and amount',
          'icon': Icons.account_balance_rounded,
          'has_pdf': true,
          'has_excel': true,
          'accent': AppColors.navyLight,
          'category': 'Financial'
        },
      ];

  Future<void> _showGenerateDialog(
      BuildContext context, Map<String, dynamic> template) async {
    DateTimeRange? range;
    bool loading = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(),
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          title: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF5C6370),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.zero,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28)),
                  ),
                  child: Icon(
                      template['icon'] as IconData? ??
                          Icons.description_rounded,
                      size: 20,
                      color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    template['name'] as String? ?? 'Report',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: Colors.white),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                const Text('Date Range',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showAppDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now());
                    if (picked != null) setS(() => range = picked);
                  },
                  borderRadius: BorderRadius.zero,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: range == null
                          ? Colors.white
                          : const Color(0xFFF3F4F6),
                      border: Border.all(
                        color: range == null
                            ? AppColors.border
                            : AppColors.borderDark,
                        width: range == null ? 1 : 1.4,
                      ),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range_rounded,
                            size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              range == null
                                  ? 'Select Date Range'
                                  : '${DateFormat('MMM dd').format(range!.start)} – ${DateFormat('MMM dd, yyyy').format(range!.end)}',
                              style: TextStyle(
                                  color: range == null
                                      ? AppColors.textTertiary
                                      : AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: range == null
                                      ? FontWeight.w400
                                      : FontWeight.w700)),
                        ),
                        if (range != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Text(
                                '${range!.end.difference(range!.start).inDays + 1} days',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textSecondary)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary))),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              // Habang tumatakbo ang generate, naka-disable at naka-loading
              // ang Proceed button — hindi na nagsasara agad ang date range
              // dialog bago pa matapos ang paggawa ng report.
              onPressed: (range == null || loading)
                  ? null
                  : () async {
                      final selected = range!;
                      setS(() => loading = true);
                      final templateKey = template['key'] as String;
                      final params = <String, dynamic>{
                        'date_from':
                            DateFormat('yyyy-MM-dd').format(selected.start),
                        'date_to':
                            DateFormat('yyyy-MM-dd').format(selected.end),
                      };
                      Map<String, dynamic>? result;
                      try {
                        // PREVIEW lang — hindi pa naka-record sa Generated
                        // Reports History. Ang Excel/PDF export sa preview modal
                        // lang ang nagsa-save ng entry.
                        result = await ref
                            .read(_reportProvider.notifier)
                            .generate(templateKey, params, preview: true);
                      } catch (e) {
                        debugPrint('[DEBUG] Generate error: $e');
                      }
                      if (!ctx.mounted) return;
                      // Tapos na ang preview fetch — isara na ang date dialog at
                      // buksan ang preview (modal) ng report.
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      dynamic rawData;
                      if (result != null) {
                        rawData = result['data'] ??
                            result['rows'] ??
                            result['records'] ??
                            result;
                        if (rawData is Map && rawData.containsKey('data')) {
                          rawData = rawData['data'];
                        }
                      }
                      final dataForPreview = rawData ?? [];
                      await _showDownloadDialog(
                          context,
                          template['name'] as String? ?? 'Report',
                          dataForPreview,
                          templateKey: templateKey,
                          parameters: params,
                          dateRange: selected);
                    },
              icon: loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_forward_rounded, size: 16),
              label: Text(loading ? 'Generating…' : 'Proceed'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C6370),
                  disabledBackgroundColor:
                      const Color(0xFF5C6370).withValues(alpha: 0.35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  shape: const RoundedRectangleBorder()),
            ),
          ],
        );
        },
      ),
    );
  }

  Future<void> _showDownloadDialog(
      BuildContext context, String title, dynamic data,
      {DateTimeRange? dateRange,
      required String templateKey,
      required Map<String, dynamic> parameters}) async {
    final rows = _normalizeRows(data);
    // Interest Report: Amount / Interest / Total lang ang columns — kapareho
    // ang laman ng table sa preview at ng na-download na PDF/Excel.
    //
    // Ang `exportRows` ay ina-update ng preview kapag nagbago ang filter
    // (Status / Lender / search), kaya ang na-export ay tugma sa nakikita sa
    // screen at hindi ang buong report.
    final isInterestReport = templateKey == kInterestReportKey;
    var exportRows = isInterestReport ? interestPreviewRows(rows) : rows;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: const RoundedRectangleBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 680),
          child: Container(
            decoration: const BoxDecoration(color: Colors.white),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: AppColors.divider)),
                  ),
                  // Isang row lang: title sa kaliwa, period (date range) sa
                  // KANAN — tabi mismo ng close button. Dati kasing nasa ilalim
                  // ng title kaya nagiging dalawang row.
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          dateRange == null
                              ? '${rows.length} record${rows.length == 1 ? '' : 's'}'
                              : '${DateFormat('MMM dd, yyyy').format(dateRange.start)} – ${DateFormat('MMM dd, yyyy').format(dateRange.end)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded,
                              size: 20, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                // Preview — aktwal na PDF (coupon) na lalabas din kapag
                // na-download, para eksaktong tugma ang preview sa file.
                // Pinch-to-zoom na (`PdfZoomViewer`): laging aktibo ang
                // pinch/wheel/double-tap, hindi katulad ng `PdfPreview` na
                // kailangan pa ng double-tap bago gumana ang gesture.
                //
                // Interest Report lang ang hindi PDF dito: dashboard-style na
                // preview (filter bar + summary cards + Amount / Interest /
                // Total na table + numbered pagination) — pareho pa rin ang
                // columns ng na-download na file dahil `exportRows` ang
                // ipinapasa sa Excel/PDF export.
                Expanded(
                  child: isInterestReport
                      ? LoanRecordsPreview(
                          rows: rows,
                          onFilteredChanged: (filtered) =>
                              exportRows = filtered,
                        )
                      : PdfZoomViewer(
                          buildDocument: () =>
                              buildPdf(title: title, rows: rows),
                        ),
                ),
                // Actions
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(
                      border:
                          Border(top: BorderSide(color: AppColors.divider))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final saved = await _recordExport(
                              templateKey, parameters,
                              format: 'xlsx');
                          if (!context.mounted) return;
                          if (!saved) _notifyExportNotRecorded(context);
                          await _downloadExcel(context, title, exportRows);
                        },
                        icon: const Icon(Icons.table_chart_rounded,
                            color: AppColors.riderGreen, size: 16),
                        label: const Text('Excel',
                            style: TextStyle(color: AppColors.riderGreen)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final saved = await _recordExport(
                              templateKey, parameters,
                              format: 'pdf');
                          if (!context.mounted) return;
                          if (!saved) _notifyExportNotRecorded(context);
                          await _downloadPdf(context, title, exportRows);
                        },
                        icon:
                            const Icon(Icons.picture_as_pdf_rounded, size: 16),
                        label: const Text('Download PDF'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white),
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

  /// Dito lang naka-record ang report sa Generated Reports History — sa
  /// mismong pagpindot ng Excel o PDF mula sa preview, hindi sa Proceed.
  Future<bool> _recordExport(String templateKey,
      Map<String, dynamic> parameters,
      {required String format}) async {
    final res = await ref.read(_reportProvider.notifier).generate(
          templateKey,
          parameters,
          format: format,
        );
    return res != null;
  }

  void _notifyExportNotRecorded(BuildContext context) {
    if (!context.mounted) return;
    context.showSnackBarAsToast(const SnackBar(
        content: Text('File downloaded, pero hindi na-save sa report history'),
        backgroundColor: AppColors.warning));
  }

  Future<void> _downloadPdf(BuildContext context, String title,
      List<Map<String, dynamic>> rows) async {
    try {
      final bytes = await buildPdf(title: title, rows: rows);
      await saveFile(bytes, '${sanitizeFileName(title)}.pdf');
      if (context.mounted) _notifyDownload(context, title, 'PDF');
    } catch (e) {
      if (context.mounted) _notifyError(context);
    }
  }

  Future<void> _downloadExcel(BuildContext context, String title,
      List<Map<String, dynamic>> rows) async {
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
    context.showSnackBarAsToast(SnackBar(
        content: Text('$title downloaded as $format'),
        backgroundColor: AppColors.success));
  }

  void _notifyError(BuildContext context) {
    if (!context.mounted) return;
    context.showSnackBarAsToast(const SnackBar(
        content: Text('Failed to download report'),
        backgroundColor: AppColors.error));
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

  /// Shimmer na tugma sa table layout (header + rows).
  Widget _buildShimmer() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ShimmerLoader(width: 140, height: 20),
            const SizedBox(height: 16),
            for (var i = 0; i < 8; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: ShimmerLoader(height: 56),
              ),
            const SizedBox(height: 24),
            const ShimmerLoader(width: 200, height: 20),
            const SizedBox(height: 16),
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: ShimmerLoader(height: 56),
              ),
          ],
        ),
      );
}

/// Maliit na chip para sa available formats (PDF / XLSX).
class _FormatChip extends StatelessWidget {
  final String label;
  final Color color;
  const _FormatChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      );
}

/// "Generate" button ng bawat row — gradient sa accent color ng template.
class _GenerateButton extends StatelessWidget {
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;
  const _GenerateButton(
      {required this.accent, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.85)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Text('Generate',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ],
          ),
        ),
      );
}

/// Prev/Next button ng client-side pagination (kapareho ng list screens).
class _PageBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PageBtn(
      {required this.icon, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
            color: enabled ? Colors.white : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border)),
        child: Icon(icon,
            size: 18,
            color: enabled ? AppColors.textPrimary : AppColors.textTertiary),
      ),
    );
  }
}
