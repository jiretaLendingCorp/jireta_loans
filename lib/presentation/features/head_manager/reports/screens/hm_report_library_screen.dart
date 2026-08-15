// lib/presentation/features/head_manager/reports/screens/hm_report_library_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/report_remote_datasource.dart';
import '../../../../shared/utils/file_downloader.dart';
import '../../../../shared/utils/report_exporter.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

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
    bindRealtimeRefresh(['reports'], refresh: init);
    init();
  }

  Future<void> init() async {
    state = state.copyWith(isLoading: true);
    try {
      final templates = await _ds.getReportList();
      final history = await _ds.getRawHistory();
      state = state.copyWith(
        templates: templates,
        history: history,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
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

class HmReportLibraryScreen extends ConsumerWidget {
  const HmReportLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_reportProvider);
    return WebScaffold(
      title: 'Reports',
      actions: [
        IconButton(
            onPressed: () => ref.read(_reportProvider.notifier).init(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh'),
        const SizedBox(width: 12),
      ],
      body: state.isLoading
          ? const ShimmerLoader()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Report Templates'),
                  const SizedBox(height: 16),
                  _buildTemplateGrid(context, ref, state),
                  const SizedBox(height: 32),
                  _buildSectionTitle('Generated Reports History'),
                  const SizedBox(height: 16),
                  _buildHistory(context, state),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) => Row(
        children: [
          Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ],
      );

  Widget _buildTemplateGrid(
      BuildContext context, WidgetRef ref, _ReportState state) {
    final templates =
        state.templates.isNotEmpty ? state.templates : _defaultTemplates();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.6,
      ),
      itemCount: templates.length,
      itemBuilder: (ctx, i) =>
          _buildTemplateCard(context, ref, templates[i], state.isGenerating),
    );
  }

  Widget _buildTemplateCard(BuildContext context, WidgetRef ref,
      Map<String, dynamic> t, bool generating) {
    return _HoverCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: generating ? null : () => _showGenerateDialog(context, ref, t),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: AppColors.deepNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(
                        t['icon'] as IconData? ?? Icons.assessment_outlined,
                        size: 18,
                        color: AppColors.deepNavy),
                  ),
                  const Spacer(),
                  if (t['has_pdf'] == true)
                    const Icon(Icons.picture_as_pdf_outlined,
                        size: 14, color: AppColors.error),
                  const SizedBox(width: 4),
                  if (t['has_excel'] == true)
                    const Icon(Icons.table_chart_outlined,
                        size: 14, color: AppColors.riderGreen),
                ],
              ),
              const SizedBox(height: 10),
              Text(t['name'] as String? ?? 'Report',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 4),
              Expanded(
                child: Text(t['description'] as String? ?? '',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: generating
                    ? null
                    : () => _showGenerateDialog(context, ref, t),
                icon: generating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download_outlined, size: 14),
                label: const Text('Generate', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black87,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistory(BuildContext context, _ReportState state) {
    if (state.history.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border)),
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text('No reports generated yet',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ),
      );
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border)),
      child: Column(
        children: state.history.asMap().entries.map((e) {
          final r = e.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: e.key.isEven
                  ? Colors.white
                  : AppColors.surfaceVariant.withValues(alpha: 0.3),
              border:
                  const Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                const Icon(Icons.description_outlined,
                    size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['report_name'] as String? ?? '-',
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 14)),
                      Text(_formatDate(r['created_at']),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                if (r['pdf_url'] != null || r['data'] != null)
                  TextButton.icon(
                    onPressed: () => _downloadPdf(
                      context,
                      r['report_name'] as String? ?? 'Report',
                      _normalizeRows(r['data']),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined,
                        size: 16, color: AppColors.error),
                    label: const Text('PDF',
                        style: TextStyle(color: AppColors.error, fontSize: 12)),
                  ),
                if (r['xlsx_url'] != null || r['data'] != null)
                  TextButton.icon(
                    onPressed: () => _downloadExcel(
                      context,
                      r['report_name'] as String? ?? 'Report',
                      _normalizeRows(r['data']),
                    ),
                    icon: const Icon(Icons.table_chart_outlined,
                        size: 16, color: AppColors.riderGreen),
                    label: const Text('Excel',
                        style: TextStyle(
                            color: AppColors.riderGreen, fontSize: 12)),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Map<String, dynamic>> _defaultTemplates() => [
        {
          'key': 'loan_summary',
          'name': 'Loan Summary Report',
          'description': 'Overview of all loans by status and amount',
          'icon': Icons.summarize_outlined,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'collection_report',
          'name': 'Collection Report',
          'description': 'Cash and GCash collections summary',
          'icon': Icons.local_shipping_outlined,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'payment_report',
          'name': 'Payment Report',
          'description': 'All payments processed in date range',
          'icon': Icons.payments_outlined,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'borrower_report',
          'name': 'Lender Report',
          'description': 'All registered lenders and their status',
          'icon': Icons.person_outlined,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'rider_report',
          'name': 'Rider Report',
          'description': 'Rider performance and assignment history',
          'icon': Icons.delivery_dining_outlined,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'employee_report',
          'name': 'Employee Report',
          'description': 'Employee activity and processing history',
          'icon': Icons.people_outline,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'financial_report',
          'name': 'Financial Report',
          'description': 'Revenue, interest, and penalty totals',
          'icon': Icons.monetization_on_outlined,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'overdue_report',
          'name': 'Overdue Loans Report',
          'description': 'Loans with delayed payments',
          'icon': Icons.warning_outlined,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'audit_report',
          'name': 'Audit Report',
          'description': 'System activity and audit trail',
          'icon': Icons.history_outlined,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'ci_report',
          'name': 'CI Report',
          'description': 'Credit investigation assignments and outcomes',
          'icon': Icons.search_outlined,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'account_upgrade_report',
          'name': 'Account Upgrade Report',
          'description': 'Account upgrade submission and verification status',
          'icon': Icons.verified_user_outlined,
          'has_pdf': true,
          'has_excel': true
        },
        {
          'key': 'disbursement_report',
          'name': 'Disbursement Report',
          'description': 'Loan disbursements by method and amount',
          'icon': Icons.account_balance_outlined,
          'has_pdf': true,
          'has_excel': true
        },
      ];

  Future<void> _showGenerateDialog(BuildContext context, WidgetRef ref,
      Map<String, dynamic> template) async {
    DateTimeRange? range;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Generate: ${template['name']}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Select date range for this report:'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setS(() => range = picked);
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(range == null
                      ? 'Select Date Range'
                      : '${DateFormat('MMM dd').format(range!.start)} – ${DateFormat('MMM dd, yyyy').format(range!.end)}'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: range == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final result = await ref
                          .read(_reportProvider.notifier)
                          .generate(
                        template['key'] as String,
                        {
                          'date_from': range!.start.toIso8601String(),
                          'date_to': range!.end.toIso8601String()
                        },
                      );
                      if (!context.mounted) return;
                      if (result != null) {
                        await _showDownloadDialog(
                          context,
                          template['name'] as String? ?? 'Report',
                          result['data'],
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Failed to generate report'),
                              backgroundColor: AppColors.error),
                        );
                      }
                    },
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Generate'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDownloadDialog(
      BuildContext context, String title, dynamic data) async {
    final rows = _normalizeRows(data);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Report Ready'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '${rows.length} record${rows.length == 1 ? '' : 's'} retrieved. Choose a format to download.',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              if (!context.mounted) return;
              await _downloadExcel(context, title, rows);
            },
            icon: const Icon(Icons.table_chart_outlined,
                color: AppColors.riderGreen),
            label: const Text('Excel',
                style: TextStyle(color: AppColors.riderGreen)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              if (!context.mounted) return;
              await _downloadPdf(context, title, rows);
            },
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Download PDF'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadPdf(BuildContext context,
      String title, List<Map<String, dynamic>> rows) async {
    try {
      final bytes = await buildPdf(title: title, rows: rows);
      await saveFile(bytes, '${sanitizeFileName(title)}.pdf');
      if (context.mounted) _notifyDownload(context, title, 'PDF');
    } catch (e) {
      if (context.mounted) _notifyError(context);
    }
  }

  Future<void> _downloadExcel(BuildContext context,
      String title, List<Map<String, dynamic>> rows) async {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title downloaded as $format'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _notifyError(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Failed to download report'),
          backgroundColor: AppColors.error),
    );
  }

  List<Map<String, dynamic>> _normalizeRows(dynamic data) {
    if (data is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in data) {
      if (item is Map) {
        out.add(item.map((k, v) => MapEntry(k.toString(), _flatten(v))));
      }
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

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    try {
      return DateFormat('MMM dd, yyyy hh:mm a')
          .format(DateTime.parse(d.toString()));
    } catch (_) {
      return d.toString();
    }
  }
}

class _HoverCard extends StatefulWidget {
  final Widget child;
  const _HoverCard({required this.child});

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _hover
                    ? AppColors.gold.withValues(alpha: 0.5)
                    : AppColors.border),
            boxShadow: _hover
                ? [
                    BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : [],
          ),
          child: widget.child,
        ),
      );
}
