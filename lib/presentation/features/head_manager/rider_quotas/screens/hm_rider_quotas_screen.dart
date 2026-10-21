// lib/presentation/features/head_manager/rider_quotas/screens/hm_rider_quotas_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/rider_quota_model.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/filter_dropdown.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/rider_quota_progress.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../../../shared/widgets/tables/records_pagination.dart';
import '../../rider_monitoring/widgets/rider_monitoring_section_tabs.dart';
import '../../rider_monitoring/widgets/rider_monitoring_stat_card.dart';
import '../providers/hm_rider_quotas_provider.dart';
import '../widgets/rider_quota_form_dialog.dart';

/// Quotas tab ng Rider Monitoring — HM **at employee** (read-only) na page.
///
/// Ang quota LIST ay bukas sa HM + EMPLOYEE (`collections-view?fn=rider-quotas`),
/// pero HM lang ang pwedeng mag-assign/edit/close (`collections-manage`). Kaya
/// kapag employee ang tumitingin: `canManage: false` → walang "Assign quota"
/// button at walang edit/close actions, at employee URL ang tabs.
class HmRiderQuotasScreen extends ConsumerStatefulWidget {
  /// Ruta ng Monitoring tab.
  final String monitoringRoute;

  /// Ruta ng Quotas tab (aktibong tab).
  final String quotasRoute;

  /// `false` = read-only (employee): walang assign/edit/close quota.
  final bool canManage;

  const HmRiderQuotasScreen({
    super.key,
    this.monitoringRoute = RouteConstants.hmRiderMonitoring,
    this.quotasRoute = RouteConstants.hmRiderMonitoringQuotas,
    this.canManage = true,
  });

  @override
  ConsumerState<HmRiderQuotasScreen> createState() =>
      _HmRiderQuotasScreenState();
}

class _HmRiderQuotasScreenState extends ConsumerState<HmRiderQuotasScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;

  static const _sortOptions = <String, String>{
    'start_date:desc': 'Newest first',
    'start_date:asc': 'Oldest first',
    'target_amount:desc': 'Quota (high → low)',
    'confirmed_collection:desc': 'Collected (high → low)',
    'completion_percentage:desc': 'Progress (high → low)',
    'rider_name:asc': 'Rider name (A–Z)',
  };

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onDateRangeChanged(DateTimeRange? range) {
    setState(() => _dateRange = range);
    final fmt = DateFormat('yyyy-MM-dd');
    ref.read(hmRiderQuotasProvider.notifier).setDateRange(
          range == null ? null : fmt.format(range.start),
          range == null ? null : fmt.format(range.end),
        );
  }

  Future<void> _openAssignDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const RiderQuotaFormDialog(),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Rider quota assigned'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _openEditDialog(RiderQuota quota) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => RiderQuotaFormDialog(existing: quota),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Rider quota updated'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _confirmClose(RiderQuota quota) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close rider quota?'),
        content: Text(
          '${quota.riderName.isEmpty ? 'This rider' : quota.riderName} will no '
          'longer be tracked against this quota. The history and earlier '
          'results stay intact — nothing is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Close quota'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await ref
        .read(hmRiderQuotasProvider.notifier)
        .closeQuota(quota.quotaId);
    if (!mounted) return;
    if (!ok) {
      final message = ref.read(hmRiderQuotasProvider).actionError ??
          'Could not close the quota.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmRiderQuotasProvider);
    final sortValue = '${state.sortKey}:${state.sortDir}';

    return WebScaffold(
      // Kapareho ng monitoring page — isang section ito, tabs lang ang nagiba.
      title: 'Rider Collection Monitoring',
      actions: [
        IconButton(
          onPressed: () => ref.read(hmRiderQuotasProvider.notifier).refresh(),
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
      body: Container(
        color: context.cPageBg,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Monitoring / Quotas tabs — sariling URI bawat isa.
              RiderMonitoringSectionTabs(
                activeRoute: widget.quotasRoute,
                monitoringRoute: widget.monitoringRoute,
                quotasRoute: widget.quotasRoute,
              ),
              const SizedBox(height: 16),
              _QuotaSummaryCards(summary: state.summary),
              const SizedBox(height: 20),
              Container(
                color: context.cSurface,
                padding: const EdgeInsets.all(16),
                child: ResponsiveSearchToolbar(
                  searchField: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search rider name...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: context.cBorder),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (v) =>
                        ref.read(hmRiderQuotasProvider.notifier).setSearch(v),
                  ),
                  trailing: [
                    SearchDateFilter(
                      value: _dateRange,
                      onChanged: _onDateRangeChanged,
                    ),
                    SearchResultsChip(count: state.total),
                    FilterDropdown<String>(
                      value: state.period,
                      icon: Icons.event_repeat_outlined,
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All periods')),
                        DropdownMenuItem(
                            value: RiderQuotaPeriod.daily,
                            child: Text('Daily')),
                        DropdownMenuItem(
                            value: RiderQuotaPeriod.weekly,
                            child: Text('Weekly')),
                        DropdownMenuItem(
                            value: RiderQuotaPeriod.monthly,
                            child: Text('Monthly')),
                      ],
                      onChanged: (v) => ref
                          .read(hmRiderQuotasProvider.notifier)
                          .setPeriod(v ?? ''),
                    ),
                    FilterDropdown<String>(
                      value: state.statusFilter,
                      icon: Icons.filter_list_rounded,
                      items: const [
                        DropdownMenuItem(
                            value: 'all', child: Text('All statuses')),
                        DropdownMenuItem(
                            value: RiderQuotaStatus.active,
                            child: Text('Active')),
                        DropdownMenuItem(
                            value: RiderQuotaStatus.upcoming,
                            child: Text('Upcoming')),
                        DropdownMenuItem(
                            value: RiderQuotaStatus.completed,
                            child: Text('Completed')),
                        DropdownMenuItem(
                            value: RiderQuotaStatus.expired,
                            child: Text('Expired')),
                        DropdownMenuItem(
                            value: RiderQuotaStatus.inactive,
                            child: Text('Inactive')),
                      ],
                      onChanged: (v) => ref
                          .read(hmRiderQuotasProvider.notifier)
                          .setStatus(v ?? 'all'),
                    ),
                    FilterDropdown<String>(
                      value: _sortOptions.containsKey(sortValue)
                          ? sortValue
                          : 'start_date:desc',
                      icon: Icons.swap_vert_rounded,
                      items: _sortOptions.entries
                          .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ))
                          .toList(),
                      onChanged: (v) => ref
                          .read(hmRiderQuotasProvider.notifier)
                          .setSort(v ?? 'start_date:desc'),
                    ),
                    // HM lang ang pwedeng mag-assign (collections-manage).
                    if (widget.canManage)
                      FilledButton.icon(
                        onPressed: state.isSaving ? null : _openAssignDialog,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Assign quota'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (state.isLoading && state.rows.isEmpty)
                const _Skeleton()
              else if (state.error != null && state.rows.isEmpty)
                ErrorStateWidget(
                  message: state.error!,
                  onRetry: () =>
                      ref.read(hmRiderQuotasProvider.notifier).refresh(),
                )
              else if (state.rows.isEmpty)
                EmptyStateWidget(
                  icon: Icons.flag_outlined,
                  title: 'No rider quotas found',
                  message: state.statusFilter == 'all' && state.search.isEmpty
                      ? 'Assign a quota to start tracking rider collection '
                          'targets.'
                      : 'Try a different search, period, status or date range.',
                  actionLabel: 'Clear filters',
                  onAction: () {
                    _searchCtrl.clear();
                    setState(() => _dateRange = null);
                    final notifier = ref.read(hmRiderQuotasProvider.notifier);
                    notifier.setSearch('');
                    notifier.setPeriod('');
                    notifier.setStatus('all');
                    notifier.setDateRange(null, null);
                  },
                )
              else ...[
                RiderQuotaTable(
                  state: state,
                  // Employee: `null` ang callbacks → walang edit/close, at
                  // "Read-only" ang tooltip ng lock icon.
                  onEdit: widget.canManage ? _openEditDialog : null,
                  onClose: widget.canManage ? _confirmClose : null,
                ),
                const SizedBox(height: 12),
                RecordsPagination(
                  currentPage: state.page,
                  totalPages: state.totalPages,
                  onPageChange: (p) =>
                      ref.read(hmRiderQuotasProvider.notifier).setPage(p),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Limang summary card — aktwal na records lang, walang mock value.
class _QuotaSummaryCards extends StatelessWidget {
  final RiderQuotaSummary summary;
  const _QuotaSummaryCards({required this.summary});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 980
            ? 5
            : constraints.maxWidth >= 700
                ? 3
                : 2;
        final width = (constraints.maxWidth - (perRow - 1) * 10) / perRow - 1;
        final cards = <Widget>[
          RiderMonitoringStatCard(
            title: 'Riders with Active Quotas',
            value: '${summary.activeRiders}',
            icon: Icons.delivery_dining_outlined,
            color: AppColors.info,
            subtitle: '${summary.openQuotas} open',
          ),
          RiderMonitoringStatCard(
            title: 'Total Assigned Quota',
            value: summary.assignedQuota.toPeso(),
            icon: Icons.flag_outlined,
            color: AppColors.lenderBlueLight,
          ),
          RiderMonitoringStatCard(
            title: 'Total Confirmed Collections',
            value: summary.confirmedTotal.toPeso(),
            icon: Icons.verified_outlined,
            color: AppColors.success,
          ),
          RiderMonitoringStatCard(
            title: 'Remaining Quota',
            value: summary.remainingTotal.toPeso(),
            icon: Icons.pending_actions_outlined,
            color: AppColors.warning,
          ),
          RiderMonitoringStatCard(
            title: 'Riders Who Met Targets',
            value: '${summary.ridersMet}',
            icon: Icons.emoji_events_outlined,
            color: AppColors.success,
            subtitle: '${summary.expiredQuotas} expired',
          ),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards.map((c) => SizedBox(width: width, child: c)).toList(),
        );
      },
    );
  }
}

/// Desktop quota table — public para direkta itong ma-test sa desktop width
/// (tabular headers) at sa maliit na width (stacked cards).
class RiderQuotaTable extends StatelessWidget {
  final HmRiderQuotasState state;

  /// `null` = read-only (employee): walang edit/close, lock icon lang ang
  /// lalabas sa Actions column.
  final ValueChanged<RiderQuota>? onEdit;
  final ValueChanged<RiderQuota>? onClose;

  const RiderQuotaTable({
    super.key,
    required this.state,
    this.onEdit,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveListCard(
      // Ang content area sa 1366px desktop ay ~1060px pagkatapos ng sidebar at
      // padding. Kapag mas mataas ito, bumabagsak sa stacked-card layout at
      // hindi na tabular ang quota table — 1000px lang para tabular pa rin sa
      // desktop; mas maliit dito ay card layout na (tablet/mobile).
      minTableWidth: 1000,
      variant: ResponsiveListVariant.premium,
      columns: const [
        ResponsiveCol('Rider', icon: Icons.person_outline, flex: 3),
        ResponsiveCol('Period', icon: Icons.event_repeat_outlined, flex: 2),
        ResponsiveCol('Quota',
            icon: Icons.flag_outlined, flex: 2, alignEnd: true),
        ResponsiveCol('Confirmed',
            icon: Icons.verified_outlined, flex: 2, alignEnd: true),
        ResponsiveCol('Remaining',
            icon: Icons.pending_actions_outlined, flex: 2, alignEnd: true),
        ResponsiveCol('Progress', icon: Icons.insights_outlined, flex: 2),
        ResponsiveCol('Start', icon: Icons.event_available_outlined, flex: 2),
        ResponsiveCol('End', icon: Icons.event_busy_outlined, flex: 2),
        ResponsiveCol('Status', icon: Icons.sell_outlined, flex: 2),
      ],
      actionsCol: const ResponsiveActionsCol(
        label: 'Actions',
        icon: Icons.bolt_outlined,
        flex: 2,
        alignEnd: true,
      ),
      rows: state.rows.map((q) => _row(context, q)).toList(growable: false),
    );
  }

  ResponsiveRow _row(BuildContext context, RiderQuota q) {
    final dateFmt = DateFormat('MMM d, y');
    return ResponsiveRow(
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              q.riderName.isEmpty ? 'Unnamed rider' : q.riderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.cTextPrimary,
              ),
            ),
            if (q.phoneNumber != null && q.phoneNumber!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                q.phoneNumber!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: context.cTextSecondary),
              ),
            ],
          ],
        ),
        Text(
          RiderQuotaPeriod.label(q.period),
          style: TextStyle(fontSize: 13, color: context.cTextPrimary),
        ),
        Text(
          q.targetAmount.toPeso(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.cTextPrimary,
          ),
        ),
        Text(
          q.confirmedCollection.toPeso(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.success,
          ),
        ),
        Text(
          q.remainingTarget.toPeso(),
          style: TextStyle(fontSize: 13, color: context.cTextPrimary),
        ),
        RiderQuotaProgress(
          percent: q.completionPercentage,
          achieved: q.achieved,
        ),
        Text(
          q.startDate == null ? '—' : dateFmt.format(q.startDate!),
          style: TextStyle(fontSize: 12, color: context.cTextSecondary),
        ),
        Text(
          q.endDate == null ? '—' : dateFmt.format(q.endDate!),
          style: TextStyle(fontSize: 12, color: context.cTextSecondary),
        ),
        _QuotaStatusBadge(status: q.status),
      ],
      // Dapat sa `actions` slot ito — hindi sa `cells` — para lumabas sa
      // desktop ACTIONS column at sa mobile card actions area.
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (q.isEditable && onEdit != null && onClose != null)
            IconButton(
              onPressed: () => onEdit!(q),
              tooltip: 'Edit quota',
              visualDensity: VisualDensity.compact,
              splashRadius: 18,
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          if (q.isEditable && onEdit != null && onClose != null)
            IconButton(
              onPressed: () => onClose!(q),
              tooltip: 'Close quota',
              visualDensity: VisualDensity.compact,
              splashRadius: 18,
              icon: const Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: AppColors.statusRejected,
              ),
            ),
          if (!q.isEditable || onEdit == null || onClose == null)
            Tooltip(
              message: onEdit == null || onClose == null
                  ? 'Read-only — head manager lang ang pwedeng mag-edit ng quota'
                  : 'Historical quota — read-only',
              child: Icon(
                Icons.lock_clock_outlined,
                size: 18,
                color: context.cTextTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

class _QuotaStatusBadge extends StatelessWidget {
  final String status;
  const _QuotaStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      RiderQuotaStatus.active => AppColors.success,
      RiderQuotaStatus.upcoming => AppColors.info,
      RiderQuotaStatus.completed => AppColors.lenderBlueLight,
      RiderQuotaStatus.expired => AppColors.statusRejected,
      _ => AppColors.textTertiary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        RiderQuotaStatus.label(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: List.generate(
            3,
            (i) => Expanded(
              child: Container(
                height: 104,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: context.cSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 260,
          decoration: BoxDecoration(
            color: context.cSurface,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ],
    );
  }
}
