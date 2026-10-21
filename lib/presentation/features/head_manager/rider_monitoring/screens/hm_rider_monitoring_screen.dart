// lib/presentation/features/head_manager/rider_monitoring/screens/hm_rider_monitoring_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/rider_collection_monitoring_model.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/filter_dropdown.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../../../shared/widgets/tables/records_pagination.dart';
import '../providers/hm_rider_monitoring_provider.dart';
import '../widgets/rider_monitoring_section_tabs.dart';
import '../widgets/rider_monitoring_stat_card.dart';

/// Rider Collection Monitoring — HM **at employee** (read-only) na page.
///
/// Isang screen lang ito para sa dalawang role: ang ruta lang ang pinag-iba
/// (`/hm/rider-monitoring*` vs `/employee/rider-monitoring*`) para tama ang
/// deep links at browser back. May Quotas tab din ang employee, pero
/// READ-ONLY (HM lang ang pwedeng mag-assign/edit/close sa
/// `collections-manage`).
class HmRiderMonitoringScreen extends ConsumerStatefulWidget {
  /// Ruta ng list page (ito rin ang active tab).
  final String monitoringRoute;

  /// Ruta ng details page (`:id` placeholder).
  final String detailsRoute;

  /// Ruta ng Quotas tab; `null` = walang Quotas tab (employee).
  final String? quotasRoute;

  const HmRiderMonitoringScreen({
    super.key,
    this.monitoringRoute = RouteConstants.hmRiderMonitoring,
    this.detailsRoute = RouteConstants.hmRiderMonitoringDetails,
    this.quotasRoute = RouteConstants.hmRiderMonitoringQuotas,
  });

  @override
  ConsumerState<HmRiderMonitoringScreen> createState() =>
      _HmRiderMonitoringScreenState();
}

class _HmRiderMonitoringScreenState
    extends ConsumerState<HmRiderMonitoringScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;

  static const _sortOptions = <String, String>{
    'rider_name:asc': 'Rider Name (A–Z)',
    'expected_collection:desc': 'Expected (high → low)',
    'confirmed_collection:desc': 'Confirmed (high → low)',
    'remaining_due:desc': 'Remaining Due (high → low)',
    'overdue_accounts:desc': 'Overdue Accounts (high → low)',
    'last_activity_at:desc': 'Latest Activity',
  };

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onDateRangeChanged(DateTimeRange? range) {
    setState(() => _dateRange = range);
    final fmt = DateFormat('yyyy-MM-dd');
    // Ang monitoring endpoint ay `YYYY-MM-DD` lang ang tinatanggap (due date ng
    // installment at Manila calendar day ng verified payment).
    ref.read(hmRiderMonitoringProvider.notifier).setDateRange(
          range == null ? null : fmt.format(range.start),
          range == null ? null : fmt.format(range.end),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmRiderMonitoringProvider);
    final sortValue = '${state.sortKey}:${state.sortDir}';

    return WebScaffold(
      title: 'Rider Collection Monitoring',
      actions: [
        IconButton(
          onPressed: () =>
              ref.read(hmRiderMonitoringProvider.notifier).refresh(),
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
                activeRoute: widget.monitoringRoute,
                monitoringRoute: widget.monitoringRoute,
                quotasRoute: widget.quotasRoute,
              ),
              const SizedBox(height: 16),
              RiderMonitoringSummaryCards(summary: state.summary),
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
                    onChanged: (v) => ref
                        .read(hmRiderMonitoringProvider.notifier)
                        .setSearch(v),
                  ),
                  trailing: [
                    SearchDateFilter(
                      value: _dateRange,
                      onChanged: _onDateRangeChanged,
                    ),
                    SearchResultsChip(count: state.total),
                    FilterDropdown<String>(
                      value: state.statusFilter,
                      icon: Icons.filter_list_rounded,
                      items: const [
                        DropdownMenuItem(
                            value: 'all', child: Text('All Riders')),
                        DropdownMenuItem(
                            value: 'active', child: Text('Active Collections')),
                        DropdownMenuItem(
                            value: 'overdue', child: Text('With Overdue')),
                        DropdownMenuItem(
                            value: 'has_collection',
                            child: Text('With Collections')),
                        DropdownMenuItem(
                            value: 'no_collection',
                            child: Text('No Collections')),
                      ],
                      onChanged: (v) => ref
                          .read(hmRiderMonitoringProvider.notifier)
                          .setStatus(v ?? 'all'),
                    ),
                    FilterDropdown<String>(
                      value: _sortOptions.containsKey(sortValue)
                          ? sortValue
                          : 'rider_name:asc',
                      icon: Icons.swap_vert_rounded,
                      items: _sortOptions.entries
                          .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ))
                          .toList(),
                      onChanged: (v) => ref
                          .read(hmRiderMonitoringProvider.notifier)
                          .setSort(v ?? 'rider_name:asc'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (state.isLoading && state.rows.isEmpty)
                _Skeleton()
              else if (state.error != null && state.rows.isEmpty)
                ErrorStateWidget(
                  message: state.error!,
                  onRetry: () =>
                      ref.read(hmRiderMonitoringProvider.notifier).refresh(),
                )
              else if (state.rows.isEmpty)
                EmptyStateWidget(
                  icon: Icons.delivery_dining_outlined,
                  title: 'No riders match this view',
                  message: state.statusFilter == 'all' && state.search.isEmpty
                      ? 'No active riders have been created yet.'
                      : 'Try a different search, status filter or date range.',
                  actionLabel: 'Clear filters',
                  onAction: () {
                    _searchCtrl.clear();
                    setState(() => _dateRange = null);
                    final notifier =
                        ref.read(hmRiderMonitoringProvider.notifier);
                    notifier.setSearch('');
                    notifier.setStatus('all');
                    notifier.setDateRange(null, null);
                  },
                )
              else ...[
                RiderMonitoringTable(
                  state: state,
                  detailsRoute: widget.detailsRoute,
                ),
                const SizedBox(height: 12),
                RecordsPagination(
                  currentPage: state.page,
                  totalPages: state.totalPages,
                  onPageChange: (p) =>
                      ref.read(hmRiderMonitoringProvider.notifier).setPage(p),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Anim na compact summary cards. Public para ma-test ang desktop layout
/// (dapat isang row lang at hindi naka-stretch ang bawat card).
class RiderMonitoringSummaryCards extends StatelessWidget {
  final RiderMonitoringSummary summary;
  const RiderMonitoringSummaryCards({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final performance = summary.collectionPerformance;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Isa lang na row ng anim na compact card sa desktop — sapat ang
        // lapad sa nilalaman ng card, hindi naka-stretch sa buong content area.
        final perRow = constraints.maxWidth >= 980
            ? 6
            : constraints.maxWidth >= 700
                ? 3
                : 2;
        // -1px buffer: ang exact float sum ng 6 widths + gaps ay pwedeng
        // umabot ng 1062.0000001 at ilagay ang ikaanim na card sa susunod
        // na row.
        final width = (constraints.maxWidth - (perRow - 1) * 10) / perRow - 1;
        final cards = <Widget>[
          RiderMonitoringStatCard(
            title: 'Total Active Riders',
            value: '${summary.activeRiders}',
            icon: Icons.delivery_dining_outlined,
            color: AppColors.info,
            subtitle: '${summary.openAssignments} open',
          ),
          RiderMonitoringStatCard(
            title: 'Total Assigned Accounts',
            value: '${summary.assignedAccounts}',
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.lenderBlueLight,
            subtitle: '${summary.assignedInstallments} installments',
          ),
          RiderMonitoringStatCard(
            title: 'Total Collections Due',
            value: summary.expectedCollection.toPeso(),
            icon: Icons.event_note_outlined,
            color: AppColors.info,
          ),
          RiderMonitoringStatCard(
            title: 'Total Confirmed Collections',
            value: summary.confirmedCollection.toPeso(),
            icon: Icons.verified_outlined,
            color: AppColors.success,
            // Naka-cap sa 100% (tingnan ang `riderPerformanceLabel`) — dati
            // "108.8% o…" ang lumalabas at napuputol pa.
            subtitle: performance == null
                ? null
                : '${riderPerformanceLabel(performance)} of due',
          ),
          RiderMonitoringStatCard(
            title: 'Total Overdue Accounts',
            value: '${summary.overdueAccounts}',
            icon: Icons.warning_amber_rounded,
            color: AppColors.statusRejected,
            subtitle: '${summary.overdueInstallments} installments',
          ),
          RiderMonitoringStatCard(
            title: 'Remaining Amount Due',
            value: summary.remainingDue.toPeso(),
            icon: Icons.pending_actions_outlined,
            color: AppColors.warning,
          ),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children:
              cards.map((card) => SizedBox(width: width, child: card)).toList(),
        );
      },
    );
  }
}

/// Desktop monitoring table (tabular) na bumabagsak sa stacked cards kapag
/// mas maliit sa 1000px ang content area. Public ito para direktang ma-test
/// ang layout sa desktop width (regression: cards ang lumalabas sa 1366px
/// desktop dahil masyadong mataas ang dating `minTableWidth`).
class RiderMonitoringTable extends StatelessWidget {
  final HmRiderMonitoringState state;

  /// Ruta ng details page (`:id` placeholder) — HM default; employee ang
  /// ipinapasa ng employee route para hindi tumalon sa `/hm/...`.
  final String detailsRoute;

  const RiderMonitoringTable({
    super.key,
    required this.state,
    this.detailsRoute = RouteConstants.hmRiderMonitoringDetails,
  });

  void _openDetails(BuildContext context, RiderMonitoringRow row) {
    final base = detailsRoute.replaceFirst(':id', row.riderId);
    final query = <String, String>{
      if (state.dateFrom != null) 'date_from': state.dateFrom!,
      if (state.dateTo != null) 'date_to': state.dateTo!,
    };
    context.push(
      query.isEmpty ? base : '$base?${Uri(queryParameters: query).query}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveListCard(
      // Ang content area sa 1366px desktop ay ~1060px pagkatapos ng sidebar at
      // padding. Kapag mas mataas ang minTableWidth, bumabagsak ito sa
      // stacked-card layout at nagiging napakataas ng bawat rider row. 1000px
      // lang para tabular pa rin sa desktop; mas maliit dito ay card layout na
      // (tablet/mobile) at `ResponsiveTableScroll` ang humahawak ng overflow.
      minTableWidth: 1000,
      variant: ResponsiveListVariant.premium,
      columns: const [
        ResponsiveCol('Rider', icon: Icons.person_outline, flex: 3),
        ResponsiveCol('Accounts', icon: Icons.folder_outlined, flex: 2),
        ResponsiveCol('Expected',
            icon: Icons.event_note_outlined, flex: 2, alignEnd: true),
        ResponsiveCol('Confirmed',
            icon: Icons.verified_outlined, flex: 2, alignEnd: true),
        ResponsiveCol('Remaining',
            icon: Icons.pending_actions_outlined, flex: 2, alignEnd: true),
        ResponsiveCol('Overdue',
            icon: Icons.warning_amber_outlined, flex: 2, alignEnd: true),
        // "Activity" (hindi "Last Activity") — kasya ang buong header sa
        // flex 2 na slot kahit 1366px desktop.
        ResponsiveCol('Activity', icon: Icons.schedule_outlined, flex: 2),
        // flex 3 — pinakamahabang header ("PERFORMANCE") kaya kailangan ng
        // mas malawak na slot para hindi maputol sa 1366px desktop.
        ResponsiveCol('Performance', icon: Icons.insights_outlined, flex: 3),
      ],
      // flex 2 — dati flex 1 kaya "ACTI…" lang ang nakikita sa header at
      // halos dikit na sa gilid ang view button.
      actionsCol: const ResponsiveActionsCol(
        label: 'Actions',
        icon: Icons.bolt_outlined,
        flex: 2,
        alignEnd: true,
      ),
      rows: state.rows.map((row) => _row(context, row)).toList(growable: false),
    );
  }

  ResponsiveRow _row(BuildContext context, RiderMonitoringRow row) {
    final performance = row.collectionPerformance;
    return ResponsiveRow(
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              row.riderName.isEmpty ? 'Unnamed rider' : row.riderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.cTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (row.phoneNumber != null && row.phoneNumber!.isNotEmpty)
                  row.phoneNumber!,
                if (row.plateNumber != null && row.plateNumber!.isNotEmpty)
                  row.plateNumber!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: context.cTextSecondary,
              ),
            ),
          ],
        ),
        Text(
          '${row.assignedAccounts}',
          style: TextStyle(fontSize: 13, color: context.cTextPrimary),
        ),
        Text(row.expectedCollection.toPeso(),
            style: TextStyle(fontSize: 13, color: context.cTextPrimary)),
        Text(
          row.confirmedCollection.toPeso(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.success,
          ),
        ),
        Text(
          row.remainingDue.toPeso(),
          style: TextStyle(fontSize: 13, color: context.cTextPrimary),
        ),
        Text(
          '${row.overdueAccounts}',
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                row.overdueAccounts > 0 ? FontWeight.w700 : FontWeight.w400,
            color: row.overdueAccounts > 0
                ? AppColors.statusRejected
                : context.cTextSecondary,
          ),
        ),
        // Tooltip para makita ang buong petsa + oras — ang cell ay petsa lang
        // para hindi maputol sa makitid na column.
        Tooltip(
          message: row.lastActivityAt == null
              ? 'No collection activity yet'
              : row.lastActivityAt!.toDateTimeString(),
          child: Text(
            row.lastActivityAt?.toPhilippineDate() ?? 'No activity',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: row.lastActivityAt == null
                  ? context.cTextTertiary
                  : context.cTextSecondary,
            ),
          ),
        ),
        _PerformanceCell(percent: performance),
      ],
      onTap: () => _openDetails(context, row),
      // Isang destination lang naman ang rider (details page kasama ang
      // collection history), kaya isang malinaw na VIEW icon — hindi dots at
      // hindi dalawang menu item na pareho ang pupuntahan.
      actions: Tooltip(
        message: 'View rider details & collection history',
        child: IconButton(
          onPressed: () => _openDetails(context, row),
          visualDensity: VisualDensity.compact,
          splashRadius: 18,
          icon: const Icon(
            Icons.visibility_outlined,
            size: 19,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PerformanceCell extends StatelessWidget {
  final double? percent;
  const _PerformanceCell({this.percent});

  @override
  Widget build(BuildContext context) {
    if (percent == null) {
      return Text(
        'No due',
        style: TextStyle(fontSize: 12, color: context.cTextTertiary),
      );
    }
    final clamped = percent!.clamp(0, 100).toDouble();
    final color = riderPerformanceColor(percent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // Naka-cap sa 100% ang display — ang bar ay clamped na rin.
          riderPerformanceLabel(percent),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: clamped / 100,
            minHeight: 5,
            backgroundColor: context.cSurfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: List.generate(
            3,
            (i) => const Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 12),
                child: ShimmerLoader(height: 104, borderRadius: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const ShimmerLoader(height: 260, borderRadius: 16),
      ],
    );
  }
}
