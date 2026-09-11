// lib/presentation/features/head_manager/audit/screens/hm_audit_logs_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/datasources/remote/audit_remote_datasource.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';
import '../audit_action_catalog.dart';

class _AuditState {
  final List<Map<String, dynamic>> logs;
  final bool isLoading;
  final int currentPage;
  final int totalPages;
  final String? error;
  const _AuditState(
      {this.logs = const [],
      this.isLoading = false,
      this.currentPage = 1,
      this.totalPages = 1,
      this.error});

  // Sentinel so copyWith can distinguish "not provided" from an explicit
  // `error: null` (which must CLEAR a previous error).
  static const Object _unsetError = Object();

  _AuditState copyWith({
    List<Map<String, dynamic>>? logs,
    bool? isLoading,
    int? currentPage,
    int? totalPages,
    Object? error = _unsetError,
  }) =>
      _AuditState(
          logs: logs ?? this.logs,
          isLoading: isLoading ?? this.isLoading,
          currentPage: currentPage ?? this.currentPage,
          totalPages: totalPages ?? this.totalPages,
          error: error == _unsetError ? this.error : error as String?);
}

class _AuditNotifier extends StateNotifier<_AuditState>
    with RealtimeRefreshMixin<_AuditState> {
  final AuditRemoteDataSource _ds;
  _AuditNotifier(this._ds) : super(const _AuditState()) {
    bindRealtimeRefresh(['audit_logs'], refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch({
    int page = 1,
    String? action,
    String? performedBy,
    String? startDate,
    String? endDate,
    bool silent = false,
  }) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getAuditLogs(
          page: page,
          action: action,
          performedBy: performedBy,
          startDate: startDate,
          endDate: endDate);
      final logs = (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
          logs: logs,
          isLoading: false,
          currentPage: meta['page'] as int? ?? 1,
          totalPages: meta['total_pages'] as int? ?? 1);
    } catch (e) {
      if (silent && state.logs.isNotEmpty) return;
      state = state.copyWith(
          isLoading: false, error: _describeError(e));
    }
  }

  String _describeError(Object e) {
    final message = e.toString();
    if (message.contains('Unable to reach server') ||
        message.contains('No internet')) {
      return 'Cannot connect to server. Check your connection and try again.';
    }
    if (message.contains('timed out')) {
      return 'Request timed out. Please try again.';
    }
    if (message.contains('UNAUTHORIZED')) {
      return 'Session expired. Please log in again.';
    }
    return 'Failed to load audit logs. Please try again.';
  }
}

final _auditProvider =
    AutoDisposeStateNotifierProvider<_AuditNotifier, _AuditState>((ref) {
  return _AuditNotifier(sl<AuditRemoteDataSource>());
});

class HmAuditLogsScreen extends ConsumerStatefulWidget {
  const HmAuditLogsScreen({super.key});

  @override
  ConsumerState<HmAuditLogsScreen> createState() => _HmAuditLogsScreenState();
}

class _HmAuditLogsScreenState extends ConsumerState<HmAuditLogsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String? _selectedAction;
  DateTimeRange? _dateRange;
  Map<String, dynamic>? _expandedLog;

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    ref.read(_auditProvider.notifier).fetch(
          startDate: r == null ? null : SearchDateFilter.fromParam(r.start),
          endDate: r == null ? null : SearchDateFilter.toParam(r.end),
        );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_auditProvider);
    return WebScaffold(
      title: 'Audit Logs',
      actions: [
        IconButton(
            onPressed: () => ref
                .read(_auditProvider.notifier)
                .fetch(
                    startDate: _dateRange == null
                        ? null
                        : SearchDateFilter.fromParam(_dateRange!.start),
                    endDate: _dateRange == null
                        ? null
                        : SearchDateFilter.toParam(_dateRange!.end)),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh'),
        const SizedBox(width: 12),
      ],
      body: Column(
        children: [
          _buildFilters(state),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.error != null
                    ? _buildError(state.error!)
                    : state.logs.isEmpty
                        ? _buildEmpty()
                        : _buildTable(state),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(_AuditState state) => Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: ResponsiveSearchToolbar(
          searchField: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by user name...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 400),
                  () {
                ref
                    .read(_auditProvider.notifier)
                    .fetch(performedBy: v.trim().isEmpty ? null : v.trim(),
                        startDate: _dateRange == null
                            ? null
                            : SearchDateFilter.fromParam(_dateRange!.start),
                        endDate: _dateRange == null
                            ? null
                            : SearchDateFilter.toParam(_dateRange!.end));
              });
            },
          ),
          trailing: [
            SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
            SearchResultsChip(count: state.logs.length),
            DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8)),
                child: DropdownButton<String?>(
                  value: _selectedAction,
                  hint: const Text('Filter by Action'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Actions')),
                    ...AuditActionCatalog.actions.map((a) => DropdownMenuItem(
                        value: a,
                        child: Text(AuditActionCatalog.label(a)))),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedAction = v);
                    ref.read(_auditProvider.notifier).fetch(
                        action: v,
                        startDate: _dateRange == null
                            ? null
                            : SearchDateFilter.fromParam(_dateRange!.start),
                        endDate: _dateRange == null
                            ? null
                            : SearchDateFilter.toParam(_dateRange!.end));
                  },
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildTable(_AuditState state) => LayoutBuilder(
        builder: (context, constraints) {
          // Mobile: stacked tappable cards — every field visible without
          // horizontal scrolling.
          final content = constraints.maxWidth < 820
              ? _buildMobileLogs(state)
              : ResponsiveTableScroll(
                  minWidth: 820,
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border)),
                    child: Column(
                      children: [
                        _buildHeader(),
                        const Divider(height: 1),
                        ...state.logs
                            .asMap()
                            .entries
                            .map((e) => _buildRow(e.value, e.key.isEven)),
                      ],
                    ),
                  ),
                );
          return _withPagination(content, state);
        },
      );

  /// Scrolls the table/cards together with the pagination bar — the bar sits at
  /// the end of the content instead of being pinned to the bottom edge like a
  /// footer.
  Widget _withPagination(Widget content, _AuditState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          if (state.totalPages > 1) ...[
            const SizedBox(height: 14),
            _buildPagination(state),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileLogs(_AuditState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final log in state.logs) _buildMobileLogCard(log)],
    );
  }

  Widget _buildMobileLogCard(Map<String, dynamic> log) {
    final action = log['action'] as String? ?? '-';
    final rawUser = log['performed_by_user'];
    final user = rawUser is Map<String, dynamic> ? rawUser : null;
    final performerName =
        _resolvePerformerName(user, log['performed_by'] as String?);
    final isExpanded = _expandedLog?['id'] == log['id'];
    final actionColor = _actionColor(action);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() => _expandedLog = isExpanded ? null : log),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AuditActionCatalog.label(action),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: actionColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textSecondary,
                      size: 20),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        AppColors.deepNavy.withValues(alpha: 0.1),
                    child: Text(_initials(user),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.deepNavy)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(performerName,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _labeledRow('TABLE', log['table_name'] as String? ?? '-'),
              const SizedBox(height: 8),
              _labeledRow('TIMESTAMP', _formatDateTime(log['created_at'])),
              if (isExpanded) ...[const Divider(height: 24), _buildDetails(log)],
            ],
          ),
        ),
      ),
    );
  }

  /// BEFORE / AFTER diff section shared by the desktop expandable row and the
  /// mobile card layout.
  Widget _buildDetails(Map<String, dynamic> log) {
    final oldValues = log['old_values'];
    final newValues = log['new_values'];
    return Container(
      color: AppColors.surfaceVariant,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) {
          final before = oldValues == null
              ? null
              : _buildDiffColumn(
                  title: 'BEFORE', values: oldValues, isBefore: true);
          final after = newValues == null
              ? null
              : _buildDiffColumn(
                  title: 'AFTER', values: newValues, isBefore: false);
          if (before == null && after == null) return const SizedBox.shrink();
          if (before == null) return after!;
          if (after == null) return before;
          // On narrow (mobile card) widths the two columns are stacked so each
          // side keeps the loan-record label/value row layout.
          if (c.maxWidth < 560) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [before, const SizedBox(height: 14), after]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: before),
              const SizedBox(width: 16),
              Expanded(child: after),
            ],
          );
        },
      ),
    );
  }

  /// One side of the diff — a small header plus the changed fields rendered as
  /// readable label/value rows instead of a raw `{key: value}` map dump.
  Widget _buildDiffColumn({
    required String title,
    required dynamic values,
    required bool isBefore,
  }) {
    final entries = _valueEntries(values);
    final accent = isBefore ? AppColors.error : AppColors.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 12, color: accent)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: isBefore ? AppColors.errorLight : AppColors.successLight,
              borderRadius: BorderRadius.circular(8)),
          child: entries.isEmpty
              ? Text(_formatValue(values),
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      _buildKvRow(
                        '${_humanizeKey(entries[i].key)}:',
                        _formatValue(entries[i].value),
                        showDivider: i > 0,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Label on the left (fixed width) and the value on the right — the same
  /// row presentation used by the loan record's detail cards.
  Widget _buildKvRow(String label, String value, {bool showDivider = false}) {
    return Container(
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x14000000))))
          : null,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  /// Decodes `old_values` / `new_values` into key/value pairs. PostgREST
  /// normally hands back a JSON object, but a jsonb column may also arrive as
  /// a string depending on the endpoint — both shapes are handled.
  List<MapEntry<String, dynamic>> _valueEntries(dynamic raw) {
    dynamic decoded = raw;
    if (decoded is String) {
      final trimmed = decoded.trim();
      if (trimmed.startsWith('{')) {
        try {
          decoded = jsonDecode(trimmed);
        } catch (_) {
          // Not valid JSON — fall through and render it verbatim.
        }
      }
    }
    if (decoded is Map) {
      return decoded.entries
          .map((e) => MapEntry<String, dynamic>(e.key.toString(), e.value))
          .toList();
    }
    return const [];
  }

  String _humanizeKey(String key) {
    if (key.isEmpty) return key;
    if (key.toLowerCase() == 'id') return 'ID';
    return key
        .split(RegExp(r'[_\-\s]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _formatValue(dynamic value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is List) {
      if (value.isEmpty) return '—';
      return value.map(_formatValue).join(', ');
    }
    if (value is Map) {
      return value.entries
          .map((e) =>
              '${_humanizeKey(e.key.toString())}: ${_formatValue(e.value)}')
          .join(', ');
    }
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }

  Widget _buildHeader() {
    const s = TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surfaceVariant,
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('ACTION', style: s)),
          Expanded(flex: 3, child: Text('PERFORMED BY', style: s)),
          Expanded(flex: 2, child: Text('TABLE', style: s)),
          Expanded(flex: 2, child: Text('TIMESTAMP', style: s)),
          Expanded(flex: 1, child: Text('', style: s)),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> log, bool isEven) {
    final action = log['action'] as String? ?? '-';
    final rawUser = log['performed_by_user'];
    final user = rawUser is Map<String, dynamic> ? rawUser : null;
    // Webhook/system entries (performed_by NULL) and broken joins must not
    // render as a blank performer — label them explicitly.
    // Robust fallback: if first_name/last_name are empty (e.g. Dashboard
    // Add User head_manager before 00116 had '' names), fall back to email,
    // phone, role label, or truncated UUID so the cell is never blank/?.
    final performerName = _resolvePerformerName(user, log['performed_by'] as String?);
    final isExpanded = _expandedLog?['id'] == log['id'];
    return Column(
      key: ValueKey(log['id']),
      children: [
        InkWell(
          onTap: () => setState(() => _expandedLog = isExpanded ? null : log),
          child: Container(
            color: isEven
                ? Colors.white
                : AppColors.surfaceVariant.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    AuditActionCatalog.label(action),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _actionColor(action)),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            AppColors.deepNavy.withValues(alpha: 0.1),
                        child: Text(
                          _initials(user),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.deepNavy),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(performerName,
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                    flex: 2,
                    child: Text(log['table_name'] as String? ?? '-',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary))),
                Expanded(
                    flex: 2,
                    child: Text(_formatDateTime(log['created_at']),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary))),
                Expanded(
                    flex: 1,
                    child: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.textSecondary,
                        size: 20)),
              ],
            ),
          ),
        ),
        if (isExpanded) _buildDetails(log),
      ],
    );
  }

  Widget _buildEmpty() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text('No audit logs found',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          ],
        ),
      );

  Widget _buildError(String message) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 15)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => ref.read(_auditProvider.notifier).fetch(
                startDate: _dateRange == null
                    ? null
                    : SearchDateFilter.fromParam(_dateRange!.start),
                endDate: _dateRange == null
                    ? null
                    : SearchDateFilter.toParam(_dateRange!.end)),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );

  /// Same pagination bar as the loan records screens (blue page pill between
  /// the chevrons).
  Widget _buildPagination(_AuditState state) {
    void goTo(int page) => ref.read(_auditProvider.notifier).fetch(
          page: page,
          startDate: _dateRange == null
              ? null
              : SearchDateFilter.fromParam(_dateRange!.start),
          endDate: _dateRange == null
              ? null
              : SearchDateFilter.toParam(_dateRange!.end),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Text(
            'Page ${state.currentPage} of ${state.totalPages}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
          const Spacer(),
          _PageBtn(
            icon: Icons.chevron_left_rounded,
            enabled: state.currentPage > 1,
            onTap: () => goTo(state.currentPage - 1),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${state.currentPage} / ${state.totalPages}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          _PageBtn(
            icon: Icons.chevron_right_rounded,
            enabled: state.currentPage < state.totalPages,
            onTap: () => goTo(state.currentPage + 1),
          ),
        ],
      ),
    );
  }

  /// Single-line `LABEL: value` row — label first, then a colon, then the data
  /// beside it. The label sits in a fixed-width column so every value in the
  /// card starts at the same x position.
  Widget _labeledRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text('$label:',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary)),
        ),
      ],
    );
  }

  Color _actionColor(String action) {
    if (action.contains('create') || action.contains('login')) {
      return AppColors.success;
    }
    if (action.contains('delete') ||
        action.contains('reject') ||
        action.contains('suspend')) {
      return AppColors.error;
    }
    if (action.contains('update') || action.contains('password')) {
      return AppColors.warning;
    }
    if (action.contains('export') || action.contains('report')) {
      return AppColors.info;
    }
    return AppColors.deepNavy;
  }

  String _formatDateTime(dynamic d) {
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

  String _initials(Map<String, dynamic>? user) {
    if (user == null) {
      return 'S';
    }
    final f = (user['first_name'] as String? ?? '').trim();
    final l = (user['last_name'] as String? ?? '').trim();
    final initials =
        '${f.isNotEmpty ? f[0] : ''}${l.isNotEmpty ? l[0] : ''}';
    if (initials.isNotEmpty) {
      return initials.toUpperCase();
    }
    // Fallback when names are empty (Dashboard Add User before 00116):
    // use email initial, phone initial, or role initial.
    final email = (user['email'] as String? ?? '').trim();
    if (email.isNotEmpty) {
      return email[0].toUpperCase();
    }
    final phone = (user['phone_number'] as String? ?? '').trim();
    if (phone.isNotEmpty) {
      return phone[0].toUpperCase();
    }
    final roles = user['roles'];
    String? roleName;
    if (roles is Map) {
      roleName = roles['name'] as String?;
    } else if (roles is List && roles.isNotEmpty) {
      final first = roles.first;
      if (first is Map) {
        roleName = first['name'] as String?;
      }
    }
    if (roleName != null && roleName.isNotEmpty) {
      return roleName[0].toUpperCase();
    }
    return 'U';
  }

  String _resolvePerformerName(Map<String, dynamic>? user, String? performedById) {
    if (user == null) {
      return 'System';
    }
    final f = (user['first_name'] as String? ?? '').trim();
    final l = (user['last_name'] as String? ?? '').trim();
    final full = '$f $l'.trim();
    if (full.isNotEmpty) {
      return full;
    }
    final email = (user['email'] as String? ?? '').trim();
    if (email.isNotEmpty) {
      return email;
    }
    final phone = (user['phone_number'] as String? ?? '').trim();
    if (phone.isNotEmpty) {
      return phone;
    }
    final roles = user['roles'];
    String? roleName;
    if (roles is Map) {
      roleName = roles['name'] as String?;
    } else if (roles is List && roles.isNotEmpty) {
      final first = roles.first;
      if (first is Map) {
        roleName = first['name'] as String?;
      }
    }
    if (roleName != null && roleName.isNotEmpty) {
      final label = roleName
          .split('_')
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
      return label;
    }
    if (performedById != null && performedById.isNotEmpty) {
      return 'User ${performedById.substring(0, 8)}';
    }
    return 'Unknown';
  }
}

/// Square chevron button used by the pagination bar — mirrors the loan
/// records screens.
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
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: enabled ? AppColors.border : AppColors.divider),
        ),
        child: Icon(icon,
            size: 18,
            color: enabled ? AppColors.textPrimary : AppColors.textTertiary),
      ),
    );
  }
}
