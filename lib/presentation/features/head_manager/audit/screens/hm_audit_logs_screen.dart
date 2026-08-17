// lib/presentation/features/head_manager/audit/screens/hm_audit_logs_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/audit_remote_datasource.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class _AuditState {
  final List<Map<String, dynamic>> logs;
  final bool isLoading;
  final int currentPage;
  final int totalPages;
  const _AuditState(
      {this.logs = const [],
      this.isLoading = false,
      this.currentPage = 1,
      this.totalPages = 1});
  _AuditState copyWith(
          {List<Map<String, dynamic>>? logs,
          bool? isLoading,
          int? currentPage,
          int? totalPages}) =>
      _AuditState(
          logs: logs ?? this.logs,
          isLoading: isLoading ?? this.isLoading,
          currentPage: currentPage ?? this.currentPage,
          totalPages: totalPages ?? this.totalPages);
}

class _AuditNotifier extends StateNotifier<_AuditState>
    with RealtimeRefreshMixin<_AuditState> {
  final AuditRemoteDataSource _ds;
  _AuditNotifier(this._ds) : super(const _AuditState()) {
    bindRealtimeRefresh(['audit_logs'], refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch(
      {int page = 1, String? action, String? performedBy, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final res = await _ds.getAuditLogs(
          page: page, action: action, performedBy: performedBy);
      final logs = (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
          logs: logs,
          isLoading: false,
          currentPage: meta['page'] as int? ?? 1,
          totalPages: meta['total_pages'] as int? ?? 1);
    } catch (_) {
      if (!silent) state = state.copyWith(isLoading: false);
    }
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
  String? _selectedAction;
  Map<String, dynamic>? _expandedLog;

  final _actions = [
    'login',
    'logout',
    'loan_created',
    'loan_approved',
    'loan_rejected',
    'payment',
    'user_created',
    'password_changed',
    'settings_changed',
    'report_export'
  ];

  @override
  void dispose() {
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
            onPressed: () => ref.read(_auditProvider.notifier).fetch(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh'),
        const SizedBox(width: 12),
      ],
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.logs.isEmpty
                    ? _buildEmpty()
                    : _buildTable(state),
          ),
          if (state.totalPages > 1) _buildPagination(state),
        ],
      ),
    );
  }

  Widget _buildFilters() => Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search by user or table...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => ref
                    .read(_auditProvider.notifier)
                    .fetch(performedBy: v.isEmpty ? null : v),
              ),
            ),
            const SizedBox(width: 12),
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
                    ..._actions.map((a) => DropdownMenuItem(
                        value: a,
                        child: Text(_capitalize(a.replaceAll('_', ' '))))),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedAction = v);
                    ref.read(_auditProvider.notifier).fetch(action: v);
                  },
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildTable(_AuditState state) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
    final user = log['performed_by_user'] as Map<String, dynamic>? ?? {};
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
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: _actionColor(action).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(_capitalize(action.replaceAll('_', ' ')),
                        style: TextStyle(
                            fontSize: 12,
                            color: _actionColor(action),
                            fontWeight: FontWeight.w500)),
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
                      Text(
                          '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
                              .trim(),
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
        if (isExpanded)
          Container(
            color: AppColors.surfaceVariant,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (log['old_values'] != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('BEFORE',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppColors.error)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppColors.errorLight,
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(log['old_values'].toString(),
                              style: const TextStyle(
                                  fontSize: 12, fontFamily: 'monospace')),
                        ),
                      ],
                    ),
                  ),
                if (log['old_values'] != null && log['new_values'] != null)
                  const SizedBox(width: 16),
                if (log['new_values'] != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AFTER',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppColors.success)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppColors.successLight,
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(log['new_values'].toString(),
                              style: const TextStyle(
                                  fontSize: 12, fontFamily: 'monospace')),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
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

  Widget _buildPagination(_AuditState state) => Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
                onPressed: state.currentPage > 1
                    ? () => ref
                        .read(_auditProvider.notifier)
                        .fetch(page: state.currentPage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left)),
            Text('Page ${state.currentPage} of ${state.totalPages}'),
            IconButton(
                onPressed: state.currentPage < state.totalPages
                    ? () => ref
                        .read(_auditProvider.notifier)
                        .fetch(page: state.currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right)),
          ],
        ),
      );

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
      return DateFormat('MMM dd, yyyy hh:mm a')
          .format(DateTime.parse(d.toString()));
    } catch (_) {
      return d.toString();
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _initials(Map<String, dynamic> user) {
    final f = (user['first_name'] as String? ?? '').trim();
    final l = (user['last_name'] as String? ?? '').trim();
    final initials =
        '${f.isNotEmpty ? f[0] : ''}${l.isNotEmpty ? l[0] : ''}';
    return initials.isEmpty ? '?' : initials.toUpperCase();
  }
}
