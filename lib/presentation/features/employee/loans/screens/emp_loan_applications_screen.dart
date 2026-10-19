// lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/filter_pill_tab.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../../head_manager/ci/widgets/ci_assign_modal.dart';
import '../../../head_manager/disbursements/widgets/rider_disburse_assign_modal.dart';
import '../../../head_manager/disbursements/screens/hm_disbursement_details_screen.dart';
import '../../../head_manager/loans/providers/hm_loan_provider.dart';
import '../../../head_manager/loans/providers/hm_loan_history_provider.dart';
import '../../../head_manager/loans/widgets/approve_reject_modal.dart';
import '../../../head_manager/loans/widgets/loan_details_side_panel.dart';
import '../../../head_manager/in_office/providers/hm_in_office_provider.dart';
import '../../../head_manager/in_office/widgets/in_office_wizard.dart';
import '../../../head_manager/disbursements/providers/hm_disbursement_provider.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../../core/errors/error_handler.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class EmpLoanApplicationsScreen extends ConsumerStatefulWidget {
  const EmpLoanApplicationsScreen({super.key});

  @override
  ConsumerState<EmpLoanApplicationsScreen> createState() =>
      _EmpLoanApplicationsScreenState();
}

class _EmpLoanApplicationsScreenState
    extends ConsumerState<EmpLoanApplicationsScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;
  final _scrollCtrl = ScrollController();
  // In-Office / Disbursements / Loan History ay may SARILING URI ngayon
  // (`/hm/loan-applications/in-office`, `.../disbursements`, `.../history`).
  // Ang URL ang source of truth ng tab — hindi na local state.
  String? _lastRouteTab;
  String _inOfficeSearch = '';

  // Pipeline tabs become dropdown; Active & In-Office remain as pills per request
  final _dropdownTabs = const [
    FilterTabDef('all', 'All', Icons.layers_outlined),
    FilterTabDef('pending', 'Pending CI', Icons.hourglass_top_rounded),
    FilterTabDef('under_review', 'Under Review', Icons.rate_review_outlined),
    FilterTabDef('ci_required', 'CI Required', Icons.search_outlined),
    FilterTabDef('ci_assigned', 'CI Assigned', Icons.assignment_ind_outlined),
    FilterTabDef('ci_completed', 'CI Completed', Icons.verified_outlined),
  ];
  final _pillTabs = const [
    // "Ongoing Loan" (dating "Active Loan") — ito ang buong pangalan ng
    // aktibong loan; "Ongoing" lang ang status label nito sa table.
    FilterTabDef(
        'active', 'Ongoing Loan', Icons.account_balance_wallet_outlined),
    // Tinanggal ang "Completed" tab — nasa Previous Loan na ito.
    FilterTabDef('in_office', 'In-Office Application', Icons.storefront_outlined),
    FilterTabDef('disbursements', 'Disbursements', Icons.payments_outlined),
    // Tapos nang magbayad (`completed`) + malapit nang matapos (isang
    // installment na lang ang natitira) — progreso ng bayad kada loan ang
    // pokus nito, kaya naka-base sa `loans-view?fn=get-history`. "Previous
    // Loan" ang label nito sa UI; `loan_history` pa rin ang URI/key.
    FilterTabDef('loan_history', 'Previous Loan', Icons.history_rounded),
  ];

  /// Manila-day bounds ng napiling filter — `null` kapag walang date filter.
  String? get _dateFromParam =>
      _dateRange == null ? null : SearchDateFilter.fromParam(_dateRange!.start);
  String? get _dateToParam =>
      _dateRange == null ? null : SearchDateFilter.toParam(_dateRange!.end);

  /// Tab mula sa URL — `null` kapag nasa base `/hm/loan-records`.
  static String? _tabFromPath(GoRouterState state) {
    final path = state.uri.path;
    if (path == RouteConstants.empLoansInOffice) return 'in_office';
    if (path == RouteConstants.empLoansDisbursements) {
      return 'disbursements';
    }
    if (path == RouteConstants.empLoansHistory) return 'loan_history';
    // EMPLOYEE paths — hindi `/hm/...`. Kapag HM path ang na-navigate mula sa
    // employee session, nire-redirect ito ng role guard sa dashboard.
    if (path == RouteConstants.empLoansOngoing) return 'active';
    if (path == RouteConstants.empLoansCompleted) return 'completed';
    if (path.startsWith('/employee/loan-records/pipeline/')) {
      return state.pathParameters['status'];
    }
    return null;
  }

  static String _pipelinePath(String status) =>
      RouteConstants.empLoansPipeline.replaceFirst(':status', status);

  static String _pathForTab(String tab) {
    switch (tab) {
      case 'active':
        return RouteConstants.empLoansOngoing;
      case 'completed':
        return RouteConstants.empLoansCompleted;
      case 'in_office':
        return RouteConstants.empLoansInOffice;
      case 'disbursements':
        return RouteConstants.empLoansDisbursements;
      case 'loan_history':
        return RouteConstants.empLoansHistory;
      default:
        // Pipeline dropdown statuses (all, pending, under_review, ...).
        return _pipelinePath(tab);
    }
  }

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    final from = _dateFromParam;
    final to = _dateToParam;
    final routeTab = _tabFromPath(GoRouterState.of(context));
    // Naka-wire sa KASALUKUYANG tab: dati, ang loan list lang ang tumatanggap ng
    // date range kaya WALANG nangyayari sa In-Office at Disbursements tabs
    // kahit may napiling petsa. Sinasabayan pa rin ang loan list para hindi
    // stale ang pipeline/active/completed kapag lumipat pabalik.
    ref.read(hmLoanProvider.notifier).setDateRange(from, to);
    if (routeTab == 'in_office') {
      ref.read(hmInOfficeProvider.notifier).setDateRange(from, to);
    } else if (routeTab == 'disbursements') {
      ref.read(hmDisbursementProvider.notifier).setDateRange(from, to);
    } else if (routeTab == 'loan_history') {
      ref.read(hmLoanHistoryProvider.notifier).setDateRange(from, to);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tab = _tabFromPath(GoRouterState.of(context));
    if (tab == _lastRouteTab) return;
    final isFirst = _lastRouteTab == null;
    _lastRouteTab = tab;
    // Kapag lumipat ng tab via URL (back/forward, deep link), i-sync ang data
    // ng tab na iyon — date range kasama para tama ang laman ng listahan.
    final from = _dateFromParam;
    final to = _dateToParam;
    if (tab == null) return; // base path — loan provider state na ang bahala
    if (isFirst) {
      // Unang build (refresh / deep link): In-Office / Disbursements / Loan
      // History ay may sariling initial fetch, kaya wala nang idadagdag dito.
      // Ang loan list naman ay 'all' ang default kahit `/ongoing` o
      // `/completed` ang URL — kailangang i-sync, kung hindi ay kasama sa
      // Ongoing Loan tab ang overdue at completed na loan. Pagkatapos ng
      // frame ito gawin: hindi pinapayagang i-modify ang provider habang
      // nagbi-build pa ang widget tree.
      if (tab == 'in_office' ||
          tab == 'disbursements' ||
          tab == 'loan_history') {
        return;
      }
      final routeTab = tab;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(hmLoanProvider.notifier).syncTab(routeTab);
      });
      return;
    }
    if (tab == 'in_office') {
      ref.read(hmInOfficeProvider.notifier).setDateRange(from, to);
    } else if (tab == 'disbursements') {
      ref.read(hmDisbursementProvider.notifier).setDateRange(from, to);
    } else if (tab == 'loan_history') {
      ref.read(hmLoanHistoryProvider.notifier).setDateRange(from, to);
    } else {
      // Ongoing / Completed / pipeline statuses — i-apply sa loan list.
      ref.read(hmLoanProvider.notifier).syncTab(tab);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loanState = ref.watch(hmLoanProvider);
    final inOfficeState = ref.watch(hmInOfficeProvider);
    final disbState = ref.watch(hmDisbursementProvider);
    final historyState = ref.watch(hmLoanHistoryProvider);
    final effectiveTab =
        _tabFromPath(GoRouterState.of(context)) ?? loanState.tabFilter;
    final isInOffice = effectiveTab == 'in_office';
    final isDisbursements = effectiveTab == 'disbursements';
    final isLoanHistory = effectiveTab == 'loan_history';

    return WebScaffold(
      title: 'Loan Records',
      body: Container(
        color: const Color(0xFFF0F2F5),
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTabPills(effectiveTab),
              const SizedBox(height: 16),
              // Toolbar stays visible for both modes; search filters the
              // currently visible list. For In-Office we still show the
              // same outer box (no inner box) with placeholder "Search".
              // Previous Loan has its own Search & Filter panel sa tabi ng
              // table (gaya ng design), kaya hindi na kailangan ang global
              // toolbar doon. Ibang tabs: toolbar pa rin ang nagfi-filter.
              if (!isLoanHistory) ...[
                _buildToolbar(loanState, inOfficeState, disbState,
                    historyState, isInOffice, isDisbursements, isLoanHistory),
                const SizedBox(height: 16),
              ],
              if (isInOffice) ...[
                _buildInOfficeSection(inOfficeState),
              ] else if (isDisbursements) ...[
                _buildDisbursementSection(disbState),
              ] else if (isLoanHistory) ...[
                // Kasama na sa history card ang pagination footer.
                _buildLoanHistorySection(historyState),
              ] else ...[
                if (loanState.isLoading)
                  _buildLoadingShimmer()
                else if (loanState.loans.isEmpty)
                  _buildEmpty(loanState)
                else
                  _Entrance(
                    child: _buildPremiumTable(loanState.loans),
                  ),
                // Pagination bar — palaging nakikita kahit isang page lang.
                const SizedBox(height: 16),
                _buildPagination(loanState),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────── Pill Tabs + Dropdown ───────────────────────────────
  // Ongoing Loan & In-Office stay as pills; pipeline (All/Pending/etc.) is dropdown.
  Widget _buildTabPills(String active) {
    final dropdownKeys = _dropdownTabs.map((e) => e.key).toSet();
    final isDropdownActive = dropdownKeys.contains(active);
    final dropdownValue = isDropdownActive ? active : null;

    return FilterTabBar(
      dropdownLabel: 'Pipeline',
      dropdownOptions: _dropdownTabs,
      dropdownValue: dropdownValue,
      onDropdownChanged: (v) {
        // Sariling URL ang bawat pipeline status: /hm/loan-records/pipeline/<v>.
        final target = _pipelinePath(v);
        final path = GoRouterState.of(context).uri.path;
        if (path == target) {
          ref.read(hmLoanProvider.notifier).setTab(v);
        } else {
          context.go(target);
        }
      },
      // Pill tabs for Active & In-Office
      pills: _pillTabs.map((t) {
        final isActive = t.key == active;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterPillTab(
            def: t,
            active: isActive,
            onTap: () {
              // Lahat ng pill ay may sariling URI. Ang `didChangeDependencies`
              // ang naglo-load ng tamang data pagkatapos magpalit ng URL.
              final target = _pathForTab(t.key);
              if (GoRouterState.of(context).uri.path == target) {
                ref.read(hmLoanProvider.notifier).setTab(t.key);
              } else {
                context.go(target);
              }
            },
          ),
        );
      }).toList(),
    );
  }

  // ─────────────────────────────── Toolbar ───────────────────────────────
  // No inner box — single outer container with flat Search field (hint "Search").
  Widget _buildToolbar(
      HmLoanState loanState,
      HmInOfficeState inOfficeState,
      HmDisbursementState disbState,
      HmLoanHistoryState historyState,
      bool isInOffice,
      bool isDisbursements,
      bool isLoanHistory) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ResponsiveSearchToolbar(
          searchField: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: (isDisbursements || isLoanHistory)
                  ? 'Search loan number or lender...'
                  : 'Search loan applications...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) {
              if (isInOffice) {
                setState(() => _inOfficeSearch = v);
              } else if (isDisbursements) {
                ref.read(hmDisbursementProvider.notifier).setSearch(v);
              } else if (isLoanHistory) {
                ref.read(hmLoanHistoryProvider.notifier).setSearch(v);
              } else {
                ref.read(hmLoanProvider.notifier).setSearch(v);
              }
            },
          ),
          trailing: [
            SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
            SearchResultsChip(
              count: isInOffice
                  ? _filteredInOffice(inOfficeState.applications).length
                  : isDisbursements
                      ? disbState.disbursements.length
                      : isLoanHistory
                          ? historyState.totalCount
                          : loanState.totalCount,
            ),
          ],
        ),
      );

  List<Map<String, dynamic>> _filteredInOffice(
      List<Map<String, dynamic>> apps) {
    // Draft = walk-in application na hindi pa na-submit (kasama na ang mga
    // abandonadong wizard, na may draft row agad pagbukas ng "New Walk-in") —
    // hindi ito dapat lumabas dito. Submitted/converted lang ang may nangyari.
    final visible = apps
        .where((a) => (a['status'] ?? '').toString().toLowerCase() != 'draft')
        .toList();
    if (_inOfficeSearch.isEmpty) return visible;
    final q = _inOfficeSearch.toLowerCase();
    return visible.where((a) {
      final name = (a['lender_name'] ?? '').toString().toLowerCase();
      final id = (a['id'] ?? '').toString().toLowerCase();
      return name.contains(q) || id.contains(q);
    }).toList();
  }

  // ───────────────────────── In-Office (embedded) ──────────────────────────
  Widget _buildInOfficeSection(HmInOfficeState st) {
    if (st.isLoading) return _buildLoadingShimmer();
    final apps = _filteredInOffice(st.applications);
    if (apps.isEmpty) return _buildInOfficeEmpty();
    return _Entrance(child: _buildInOfficeList(apps));
  }

  // ─────────────────────── Disbursements (embedded tab) ─────────────────────
  // Nasa tabi ng In-Office pill (wala sa side nav). Tap ng row → details page
  // kung saan makikita ang Cash on Delivery proof photos ni rider.
  Widget _buildDisbursementSection(HmDisbursementState st) {
    if (st.isLoading) return _buildLoadingShimmer();
    if (st.disbursements.isEmpty) {
      return const EmptyStateWidget(
        title: 'No Disbursements',
        message: 'Loan disbursements will appear here',
        icon: Icons.account_balance_wallet_outlined,
      );
    }
    return _Entrance(child: _buildDisbursementTable(st.disbursements));
  }

  // ──────────────────────── Loan History (embedded tab) ──────────────────────
  // Mga loan na TAPOS nang bayaran (status `completed`, o outstanding 0) lang
  // — HINDI kasama ang ongoing/"for completion". Server-side ang filter
  // (`loans-view?fn=get-history`) dahil DERIVED ang outstanding balance — wala
  // itong column sa `loans` kaya hindi mai-filter sa query ng client.
  //
  // Layout: stat cards sa itaas, tapos ang Loan History table (kaliwa) at ang
  // Search & Filter + Loan Details panel (kanan) — gaya ng "Previous Loans"
  // design. Sa makitid na viewport, naka-stack ang panel sa ilalim.
  Widget _buildLoanHistorySection(HmLoanHistoryState st) {
    // Buong-table shimmer lang sa UNANG load. Kapag nag-apply ng filter/
    // search, mananatili ang table at ang Apply button lang ang maglo-load —
    // hindi na "nawawala" ang buong table tuwing filter.
    if (st.isLoading && !st.hasLoaded) return _buildLoadingShimmer();

    final filtered = st.loans;

    final tableCard = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                const Text(
                  'Loan History',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const Spacer(),
                if (st.totalCount > 0)
                  Text(
                    '${st.totalCount} ${st.totalCount == 1 ? 'loan' : 'loans'}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          if (filtered.isEmpty)
            _buildHistoryEmpty(st)
          else
            _buildLoanHistoryTable(filtered),
          const Divider(height: 1, color: AppColors.border),
          _buildHistoryPagination(st),
        ],
      ),
    );

    return _Entrance(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Previous Loans',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'View your past loan transactions and their status.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          _buildHistoryStats(st),
          const SizedBox(height: 20),
          // Filter bar sa ITAAS ng Loan History card — full width ang table
          // kaya kita lahat ng columns (hindi na kailangang mag-scroll).
          _buildHistoryFilterCard(st),
          const SizedBox(height: 16),
          tableCard,
        ],
      ),
    );
  }

  /// Apat na stat cards ng Previous Loans — Total, Completed, Ongoing,
  /// Overdue — para agad makita ang breakdown ng mga dating loan.
  Widget _buildHistoryStats(HmLoanHistoryState st) {
    final total = st.totalCount > 0 ? st.totalCount : st.loans.length;
    // Previous Loan = completed lang (server-side ang filter), kaya lahat ng
    // nasa tab na ito ay completed.
    final completed = total;
    final ongoing =
        st.loans.where((loan) => _historyStatusKey(loan) == 'ongoing').length;
    final overdue =
        st.loans.where((loan) => _historyStatusKey(loan) == 'overdue').length;
    String pct(int count) =>
        total == 0 ? '0%' : '${(count / total * 100).toStringAsFixed(1)}%';

    Widget card({
      required String title,
      required int value,
      required String subtitle,
      required IconData icon,
      required Color color,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$value',
                    style: const TextStyle(
                        fontSize: 22,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: width,
              child: card(
                title: 'Total Loans',
                value: total,
                subtitle: 'All time',
                icon: Icons.receipt_long_rounded,
                color: AppColors.info,
              ),
            ),
            SizedBox(
              width: width,
              child: card(
                title: 'Completed',
                value: completed,
                subtitle: pct(completed),
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
              ),
            ),
            SizedBox(
              width: width,
              child: card(
                title: 'Ongoing',
                value: ongoing,
                subtitle: pct(ongoing),
                icon: Icons.access_time_filled_rounded,
                color: AppColors.warning,
              ),
            ),
            SizedBox(
              width: width,
              child: card(
                title: 'Overdue',
                value: overdue,
                subtitle: pct(overdue),
                icon: Icons.cancel_rounded,
                color: AppColors.error,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Search + Date Range + Apply Filters na bar sa ITAAS ng table — walang
  /// title at walang malaking card wrapper, para hindi humaharang sa table.
  Widget _buildHistoryFilterCard(HmLoanHistoryState st) {
    const labelStyle = TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary);

    // Sariling Container ang search field (hindi InputDecoration) para
    // siguradong 48px ang taas — kapantay ng Date Range at Apply Filters.
    final searchField = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              size: 17, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => ref
                  .read(hmLoanHistoryProvider.notifier)
                  .setSearch(_searchCtrl.text.trim()),
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Search by Loan ID or client name...',
                hintStyle:
                    TextStyle(fontSize: 12, color: AppColors.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );

    final dateField = SearchDateFilter(
      value: _dateRange,
      onChanged: _onDateRangeChanged,
    );

    // Habang nag-a-apply ng filters, SPINNER LANG DITO ang lumalabas — hindi
    // na shimmer ng buong table.
    final applyButton = SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: st.isLoading
            ? null
            : () => ref
                .read(hmLoanHistoryProvider.notifier)
                .setSearch(_searchCtrl.text.trim()),
        icon: st.isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.tune_rounded, size: 17),
        label: const Text(
          'Apply Filters',
          maxLines: 1,
          softWrap: false,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.deepNavy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.deepNavy.withValues(alpha: 0.65),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );

    Widget fieldColumn(String label, Widget child) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 6),
          child,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: fieldColumn('Search', searchField)),
              const SizedBox(width: 12),
              fieldColumn('Date Range', dateField),
              const SizedBox(width: 12),
              SizedBox(width: 170, child: applyButton),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fieldColumn('Search', searchField),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: fieldColumn('Date Range', dateField),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: applyButton),
          ],
        );
      },
    );
  }

  Widget _buildHistoryEmpty(HmLoanHistoryState st) {
    final isFiltered = st.search.isNotEmpty || _dateRange != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFiltered ? Icons.search_off_rounded : Icons.history_rounded,
            size: 42,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 10),
          Text(
            isFiltered ? 'No matching loans' : 'No Previous Loans Yet',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            isFiltered
                ? 'Try a different search term or date range.'
                : 'Completed loans will appear here.',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _clearHistoryFilters,
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  void _clearHistoryFilters() {
    _searchCtrl.clear();
    if (_dateRange != null) {
      _onDateRangeChanged(null);
    }
    ref.read(hmLoanHistoryProvider.notifier).setSearch('');
  }

  /// Status key na ginagamit ng stats at ng status pill. Ang loan na tapos nang
  /// bayaran (outstanding 0) ay Completed kahit `active` pa ang hilaw na status.
  String _historyStatusKey(LoanModel loan) {
    if (loan.isFullyPaid || loan.status == 'completed') return 'completed';
    if (loan.status == 'overdue') return 'overdue';
    if (loan.status == 'active') return 'ongoing';
    return loan.status;
  }

  /// End date ng loan para sa Previous Loans table. Kapag walang `due_date`
  /// sa payload (madalas sa lumang completed loans), gamitin ang huling
  /// schedule, huling bayad, o ang huling update ng loan — hindi '—'.
  DateTime? _historyEndDate(LoanModel loan) {
    if (loan.dueDate != null) return loan.dueDate;
    final schedules = loan.schedules;
    if (schedules != null && schedules.isNotEmpty) {
      DateTime? latest;
      for (final schedule in schedules) {
        final raw = schedule['due_date'];
        final parsed = raw is String ? DateTime.tryParse(raw) : null;
        if (parsed != null && (latest == null || parsed.isAfter(latest))) {
          latest = parsed;
        }
      }
      if (latest != null) return latest;
    }
    if (loan.lastPaymentAt != null) return loan.lastPaymentAt;
    if (loan.isFullyPaid || loan.status == 'completed') return loan.updatedAt;
    final start = loan.releaseDate ?? loan.createdAt;
    if (loan.termDays > 0) return start.add(Duration(days: loan.termDays));
    if (loan.termPeriods > 0) {
      switch (loan.frequency) {
        case 'daily':
          return start.add(Duration(days: loan.termPeriods));
        case 'weekly':
          return start.add(Duration(days: loan.termPeriods * 7));
        default:
          return DateTime(start.year, start.month + loan.termPeriods, start.day);
      }
    }
    return null;
  }

  /// Term label para sa table. Kapag 0 ang `term_days`/`term_periods` sa
  /// payload, tantiyahin mula sa start at end date — hindi "0 days".
  String _historyTermLabel(LoanModel loan) {
    if (loan.termPeriods > 0) {
      final unit = _plural(loan.termPeriods, loan.termUnit);
      return '${loan.termPeriods} $unit';
    }
    if (loan.termDays > 0) {
      return '${loan.termDays} ${_plural(loan.termDays, 'days')}';
    }
    // Walang term sa payload? Tantiyahin mula sa total payable at monthly
    // due (bilang ng installments) — para may makita pa ring Term.
    if (loan.installmentAmount > 0 && loan.totalPayable > 0) {
      final periods = (loan.totalPayable / loan.installmentAmount).round();
      if (periods > 0) return '$periods ${_plural(periods, loan.termUnit)}';
    }
    final start = loan.releaseDate ?? loan.createdAt;
    final end = _historyEndDate(loan);
    if (end != null) {
      final days = end.difference(start).inDays;
      if (days >= 30) {
        final months = (days / 30).round();
        return '$months ${months == 1 ? 'month' : 'months'}';
      }
      // Same-day start/end: minimum 1 araw pa rin ang term — hindi '—'.
      return '${days <= 1 ? 1 : days} ${days <= 1 ? 'day' : 'days'}';
    }
    return '—';
  }

  /// "1 day" / "3 months" — hindi "1 days".
  String _plural(int count, String unit) =>
      count == 1 && unit.endsWith('s')
          ? unit.substring(0, unit.length - 1)
          : unit;

  /// Table ng Previous Loans — Loan ID (may pangalan ng client sa ilalim) ·
  /// Amount · Term · Installment · Start Date · End Date · Status · Actions.
  // NAKA-TABLE ito sa lahat ng desktop na lapad: `minTableWidth: 880` — sa
  // mas makitid, ang `ResponsiveListCard` mismo ang nagpapalit sa stacked
  // cards para hindi mag-overflow.
  Widget _buildLoanHistoryTable(List<LoanModel> loans) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final dayFmt = DateFormat('MMM dd, yyyy');

    return ResponsiveListCard(
      // Full-width na ang table ngayon (nasa itaas na ang filter bar), kaya
      // 880 ang minimum — kapareho ng ibang desktop tables sa screen.
      minTableWidth: 880,
      // Nasa loob na ito ng isang puting card (title + table + pagination),
      // kaya transparent na ang border/shadow ng inner table.
      radius: 0,
      outerBorder: const Border.fromBorderSide(BorderSide.none),
      outerShadow: const [],
      headerTextStyle: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.2),
      columns: const [
        ResponsiveCol('Loan ID', icon: Icons.tag_rounded, flex: 5),
        ResponsiveCol('Amount', icon: Icons.payments_outlined, flex: 4),
        ResponsiveCol('Term', icon: Icons.timelapse_rounded, flex: 3),
        ResponsiveCol('Installment',
            icon: Icons.calendar_month_outlined, flex: 4),
        ResponsiveCol('Start Date',
            icon: Icons.play_circle_outline_rounded, flex: 4),
        ResponsiveCol('End Date',
            icon: Icons.event_available_outlined, flex: 4),
        ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 4),
      ],
      actionsCol: const ResponsiveActionsCol(
          label: 'Actions',
          icon: Icons.visibility_outlined,
          width: 96,
          alignment: Alignment.topLeft),
      rowHeight: 64,
      rowPadding: const EdgeInsets.symmetric(horizontal: 16),
      rowCrossAxisAlignment: CrossAxisAlignment.start,
      rows: loans.map((loan) {
        final lenderName =
            '${loan.lenderFirstName} ${loan.lenderLastName}'.trim();
        final startDate = loan.releaseDate ?? loan.createdAt;
        final endDate = _historyEndDate(loan);
        return ResponsiveRow(
          onTap: () => _openLoanDetails(context, loan),
          cells: [
            // May right padding ang bawat cell — kung wala, dikit ang Loan ID
            // sa katabing column (walang gap ang Expanded columns).
            _cell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loan.loanNumber,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Pangalan ng client sa ILALIM ng Loan ID — para buo ang
                  // Loan ID at hindi ito napuputol ng hiwalay na column.
                  Text(
                    lenderName.isEmpty ? '—' : lenderName,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textTertiary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _cell(
              Text(
                '₱${fmt.format(loan.principalAmount)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _cell(
              Text(
                _historyTermLabel(loan),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _cell(
              Text(
                loan.installmentAmount > 0
                    ? '₱${fmt.format(loan.installmentAmount)}'
                    : '—',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _cell(
              Text(
                dayFmt.format(startDate),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _cell(
              Text(
                endDate != null ? dayFmt.format(endDate) : '—',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _cell(_buildHistoryStatusPill(loan)),
          ],
          actions: Tooltip(
            message: 'View loan details',
            child: OutlinedButton.icon(
              onPressed: () => _openLoanDetails(context, loan),
              icon: const Icon(Icons.visibility_outlined, size: 14),
              label: const Text(
                'View',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.info,
                side: BorderSide(
                    color: AppColors.info.withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(horizontal: 9),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Data cell na may right gap — walang inter-column spacing ang
  /// `ResponsiveListCard`, kaya dito nilalagay ang pagitan ng columns.
  Widget _cell(Widget child) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: child,
      );

  Widget _buildHistoryStatusPill(LoanModel loan) {
    final status = _historyStatusKey(loan);
    final (Color color, String label) = switch (status) {
      'completed' => (AppColors.success, 'Completed'),
      'ongoing' => (AppColors.warning, 'Ongoing'),
      'overdue' => (AppColors.error, 'Overdue'),
      _ => (
          AppColors.info,
          status
              .replaceAll('_', ' ')
              .split(' ')
              .map((word) =>
                  word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
              .join(' ')
        ),
    };
    // Plain na text + dot lang — walang background/border, hindi mukhang
    // clickable na button.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: 0.1),
          ),
        ),
      ],
    );
  }

  /// "Showing 1 - 10 of 12 loans" + numbered pages — footer ng history card.
  Widget _buildHistoryPagination(HmLoanHistoryState state) {
    final total = state.totalCount;
    final from = total == 0 ? 0 : (state.currentPage - 1) * 10 + 1;
    final to = total == 0 ? 0 : from + state.loans.length - 1;
    final label = total == 0
        ? 'No loans to show'
        : 'Showing $from - $to of $total ${total == 1 ? 'loan' : 'loans'}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = Text(
            label,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary),
          );
          final pager = _buildHistoryPager(state);
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                summary,
                if (state.totalPages > 1) ...[
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: pager),
                ],
              ],
            );
          }
          return Row(
            children: [
              summary,
              const Spacer(),
              if (state.totalPages > 1) pager,
            ],
          );
        },
      ),
    );
  }

  Widget _buildHistoryPager(HmLoanHistoryState state) {
    final totalPages = state.totalPages < 1 ? 1 : state.totalPages;
    final pages = _historyPageNumbers(state.currentPage, totalPages);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHistoryPageArrow(
          Icons.chevron_left_rounded,
          enabled: state.currentPage > 1,
          onTap: () => ref
              .read(hmLoanHistoryProvider.notifier)
              .load(page: state.currentPage - 1),
        ),
        const SizedBox(width: 4),
        if (pages.first > 1) ...[
          const Text('…',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          const SizedBox(width: 4),
        ],
        for (final number in pages) ...[
          _buildHistoryPageButton(
            number,
            selected: number == state.currentPage,
            onTap: () =>
                ref.read(hmLoanHistoryProvider.notifier).load(page: number),
          ),
          const SizedBox(width: 4),
        ],
        if (pages.last < totalPages) ...[
          const Text('…',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          const SizedBox(width: 4),
        ],
        _buildHistoryPageArrow(
          Icons.chevron_right_rounded,
          enabled: state.currentPage < totalPages,
          onTap: () => ref
              .read(hmLoanHistoryProvider.notifier)
              .load(page: state.currentPage + 1),
        ),
      ],
    );
  }

  List<int> _historyPageNumbers(int current, int total) {
    if (total <= 5) return List.generate(total, (index) => index + 1);
    var start = current - 2;
    if (start < 1) start = 1;
    if (start + 4 > total) start = total - 4;
    return List.generate(5, (index) => start + index);
  }

  Widget _buildHistoryPageButton(int number,
      {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.deepNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: selected ? AppColors.deepNavy : AppColors.border),
        ),
        child: Text(
          '$number',
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildHistoryPageArrow(IconData icon,
      {required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon,
            size: 17,
            color: enabled ? AppColors.textPrimary : AppColors.textTertiary),
      ),
    );
  }

  Widget _buildDisbursementTable(List<DisbursementModel> items) {
    return ResponsiveListCard(
      minTableWidth: 880,
      variant: ResponsiveListVariant.card,
      // Ang `flex` ng bawat column = TOTOONG lapad ng laman + 48px, at ang
      // kanilang kabuuan (≈948) ay halos katumbas ng available na lapad ng
      // row. Dahil dito: (a) pantay-pantay ang gap ng lahat ng column
      // (~50px) at (b) puno ang buong lapad — walang blangkong space sa dulo.
      // Loan # (LN-2026-872871 ≈ 124) · Lender (≈ 112) ·
      // Method ("Cash on Delivery" ≈ 138) · Amount (₱60,000.00 ≈ 90) ·
      // Status ("Completed" ≈ 62) · Date ("Sep 17, 2026 6:35 AM" ≈ 134).
      headerTextStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary),
      columns: const [
        ResponsiveCol('Loan #', flex: 172),
        ResponsiveCol('Lender', flex: 160),
        ResponsiveCol('Method', flex: 186),
        ResponsiveCol('Amount', flex: 138),
        ResponsiveCol('Status', flex: 110),
        ResponsiveCol('Date', flex: 182),
      ],
      // 72px ≈ eksaktong lapad ng "View" button, at naka-LEFT align (hindi
      // right) kaya ang kaliwang dulo ng "Actions" header ay nakatapat
      // mismo sa kaliwang dulo ng button (parehong x).
      actionsCol: const ResponsiveActionsCol(
          label: 'Actions',
          width: 72,
          alignment: Alignment.centerLeft,
          alignEnd: false),
      rowBorder: const Border(bottom: BorderSide(color: AppColors.divider)),
      rows: items.map((d) => _buildDisbursementRow(d)).toList(),
    );
  }

  ResponsiveRow _buildDisbursementRow(DisbursementModel d) {
    return ResponsiveRow(
      cells: [
        Text(d.loanNumber,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.deepNavy)),
        Text(d.lenderName, style: const TextStyle(fontSize: 13)),
        _disbMethodChip(d.disbursementMethod),
        Text(d.amount.toCurrency,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        StatusBadge(status: d.status),
        Text(DateFormat('MMM d, y h:mm a').format(d.createdAt),
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
      actions: Tooltip(
        message: 'View',
        child: InkWell(
          onTap: () => showHmDisbursementDetailsModal(context, d.id),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.deepNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.deepNavy.withValues(alpha: 0.14)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined,
                    size: 14, color: AppColors.deepNavy),
                SizedBox(width: 4),
                Text('View',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepNavy)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _disbMethodChip(String method) {
    final label = switch (method) {
      'gcash' => 'GCash',
      'office_cash' => 'Office Cash',
      'rider_delivery' => 'Cash on Delivery',
      _ => method,
    };
    final color = switch (method) {
      'gcash' => AppColors.info,
      'office_cash' => AppColors.success,
      'rider_delivery' => AppColors.lenderBlue,
      _ => AppColors.textSecondary,
    };
    // Plain text lang — hindi pill/button style.
    return Text(label,
        style: TextStyle(
            fontSize: 13, color: color, fontWeight: FontWeight.w600));
  }

  Widget _buildInOfficeList(List<Map<String, dynamic>> apps) {
    return ResponsiveListCard(
      minTableWidth: 940,
      // Order ng columns: Lender · Created · Status · Loan — nasa DULO ang Loan
      // (kadikit na ng action column) at pinalawak ang Lender/Created/Status
      // para punuin ang dating malaking blangkong puwang pagkatapos ng lender
      // name (flex 3 → 4 sa Lender, 4 sa Created/Loan, 3 sa Status).
      columns: const [
        ResponsiveCol('Lender', icon: Icons.person_outline, flex: 4),
        ResponsiveCol('Created', icon: Icons.event_outlined, flex: 4),
        ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 3),
        ResponsiveCol('Loan', icon: Icons.request_quote_outlined, flex: 4),
      ],
      actionsCol: ResponsiveActionsCol(
        label: 'Action',
        // ACTION label + "New Walk-in" button sa IISANG header row — kaya
        // pinalawak ang action column (140 → 236) para magkasya pareho nang
        // hindi nagsasapawan.
        //
        // Naka-centerLEFT na ngayon (dating centerRight): ito ang nagtapat ng
        // View button sa ilalim mismo ng ACTION label — kaparehong convention
        // ng ibang columns (ang icon ng header at ang content ng cell ay
        // parehong nagsisimula sa kaliwang dulo ng column). Ang "New Walk-in"
        // button ang nananatili sa dulong kanan ng header row.
        width: 236,
        alignment: Alignment.centerLeft,
        headerWidget: Row(
          // max (hindi min) para umabot sa buong lapad ng action column — dito
          // nakabitin ang Spacer na nagtutulak sa "New Walk-in" sa dulong
          // kanan habang ang ACTION label ay nasa kaliwang dulo.
          mainAxisSize: MainAxisSize.max,
          children: [
            const Icon(Icons.bolt_outlined,
                size: 12, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            const Text(
              'ACTION',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => InOfficeWizard(
                  applicationId: null,
                  onComplete: () =>
                      ref.read(hmInOfficeProvider.notifier).load(),
                ),
              ),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('New Walk-in',
                  style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 32),
              ),
            ),
          ],
        ),
      ),
      rows: apps.map((app) {
        final createdAt = parseManila(app['created_at']);
        final dateStr = createdAt != null
            ? DateFormat('MMM dd, yyyy h:mm a').format(createdAt)
            : '—';
        // Hindi 'Converted'/'Submitted' ang ipinapakita kundi ang totoong
        // progreso: 'Ongoing Loan' kapag aktibo na ang naka-link na loan, at
        // 'Upgraded Account' kapag submitted pa lang (wala pang loan).
        final (statusColor, statusLabel) = _inOfficeStatusMeta(app);
        // Kaparehong order ng `columns` sa taas: Lender · Created · Status ·
        // Loan. Ang Loan ang huling data column, kadikit ng View action.
        return ResponsiveRow(
          cells: [
            Text(
              (app['lender_name'] ?? 'Walk-in Lender').toString(),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              dateStr,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            _StatusInline(
              status: (app['status'] ?? 'submitted').toString(),
              labelOverride: statusLabel,
              colorOverride: statusColor,
            ),
            Text(
              _inOfficeLoanLabel(app),
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          actions: _InOfficeActions(app: app),
        );
      }).toList(),
    );
  }

  Widget _buildInOfficeEmpty() {
    final isFiltered = _inOfficeSearch.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.deepNavy.withValues(alpha: 0.10),
                  AppColors.gold.withValues(alpha: 0.16),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              isFiltered
                  ? Icons.search_off_rounded
                  : Icons.storefront_outlined,
              size: 32,
              color: AppColors.deepNavy.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'No matching applications' : 'No walk-in applications',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            isFiltered
                ? 'Try a different search term.'
                : 'Walk-in applications will appear here once created.',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isFiltered)
                OutlinedButton.icon(
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _inOfficeSearch = '');
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('Clear search'),
                ),
              if (isFiltered) const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => InOfficeWizard(
                    applicationId: null,
                    onComplete: () =>
                        ref.read(hmInOfficeProvider.notifier).load(),
                  ),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Walk-in'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepNavy,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── Premium Table ─────────────────────────────
  Widget _buildPremiumTable(List<LoanModel> loans) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final dateFmt = DateFormat('MMM dd, yyyy h:mm a');

    return ResponsiveListCard(
      minTableWidth: 1040,
      columns: const [
        // flex 2 (dating 3) — sapat pa rin sa loan # + pangalan, at naiuusog
        // pakaliwa ang AMOUNT (dating masyadong malawak ang puwang pagkatapos
        // ng lender name).
        ResponsiveCol('Lender & Loan', icon: Icons.person_outline, flex: 2),
        ResponsiveCol('Amount', icon: Icons.payments_outlined, flex: 2),
        // Maikling header — ang "Outstanding Balance" ay napuputol sa column
        // na ito (maxLines: 1 + ellipsis), kaya "Outstanding" ang label.
        ResponsiveCol('Outstanding',
            icon: Icons.account_balance_wallet_outlined, flex: 2),
        ResponsiveCol('Frequency', icon: Icons.repeat_rounded, flex: 2),
        // STATUS muna bago APPLIED — naiuusog pakaliwa ang status column
        // (dating nasa dulong kanan, katabi ng ACTION).
        // Status flex 2 (dating 3) + Applied flex 3 (dating 2) — pareho pa rin
        // ang kabuuang flex, kaya hindi gumagalaw ang STATUS pero umuusog
        // PAKALIWA ang APPLIED at kasya na ang buong petsa (walang "…").
        ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 2),
        ResponsiveCol('Applied', icon: Icons.event_outlined, flex: 3),
      ],
      actionsCol: const ResponsiveActionsCol(width: 96, alignment: Alignment.topLeft),
      // Fixed row height so every row stays pantay-pantay even when the
      // Status cell stacks an extra "Rider: …" line under the status.
      rowHeight: 64,
      rowPadding: const EdgeInsets.symmetric(horizontal: 16),
      rowCrossAxisAlignment: CrossAxisAlignment.start,
      rows: loans.map((loan) {
        final status = loan.displayStatus;
        final lenderName =
            '${loan.lenderFirstName} ${loan.lenderLastName}'.trim().isEmpty
                ? (loan.lenderName ?? '—')
                : '${loan.lenderFirstName} ${loan.lenderLastName}'.trim();
        // Ang outstanding balance ay ipinapakita LANG para sa CURRENT ACTIVE
        // LOAN (active/overdue = na-release at hindi pa tapos). N/A ang lahat
        // ng iba: pending, approved, rejected, at completed.
        final isCurrentActiveLoan =
            loan.status == 'active' || loan.status == 'overdue';
        return ResponsiveRow(
          onTap: () => _openDetails(context, loan.id),
          cells: [
            // Lender & Loan — LN as plain text (no pill), lender name below
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loan.loanNumber,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  lenderName.isEmpty ? '—' : lenderName,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            // Amount — plain text only, no term label
            Text(
              '₱${fmt.format(loan.principalAmount)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
            // Outstanding balance — ang totoong halaga ay para lang sa CURRENT
            // ACTIVE LOAN (active/overdue, na-release at hindi pa tapos).
            // ₱0.00 — HINDI "N/A" — ang iba (pending, approved, rejected,
            // completed): wala silang outstanding balance.
            Text(
              '₱${fmt.format(isCurrentActiveLoan ? loan.outstandingBalance : 0)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isCurrentActiveLoan
                    ? AppColors.deepNavy
                    : AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            // Frequency — flat inline, top-aligned like the other cells
            Align(
              alignment: Alignment.topLeft,
              child: _FrequencyInline(frequency: loan.paymentFrequency),
            ),
            // Status — flat inline dot + text, start-aligned pantay sa header
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusInline(status: status),
                // Delivery rider assigned → show the rider's name
                // right below the status so staff see who is
                // delivering the cash.
                if (loan.riderDeliveryAssigned &&
                    loan.status == 'approved') ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.goldDark,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          loan.deliveryRiderName != null
                              ? 'Rider: ${loan.deliveryRiderName}'
                              : 'Delivery rider assigned',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.goldDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (loan.ciStatus != null &&
                    (loan.ciStatus == 'assigned' ||
                        loan.ciStatus == 'accepted' ||
                        loan.ciStatus == 'in_progress') &&
                    loan.status == 'ci_assigned') ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.riderGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          loan.assignedRiderName != null
                              ? 'Rider: ${loan.assignedRiderName}'
                              : 'Rider assigned',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.riderGreen),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                // Overdue CI: failed task needs a new rider.
                if (loan.ciStatus != null &&
                    (loan.ciStatus == 'failed' ||
                        loan.ciStatus == 'expired') &&
                    loan.status == 'ci_assigned') ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Flexible(
                        child: Text(
                          'CI overdue — reassignment needed',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.error),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            // Applied date — start-aligned pantay sa header. Nasa dulong
            // data column na ito (dating bago ang Status).
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateFmt.format(loan.createdAt),
                  textAlign: TextAlign.start,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  _timeAgo(loan.createdAt),
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary),
                ),
              ],
            ),
          ],
          // Action — left-aligned pantay sa header
          actions: _RowActions(loan: loan, onRefresh: _onActionDone),
        );
      }).toList(),
    );
  }

  /// Loan Details panel — lumalabas sa KANAN (hindi gitnang dialog) kasama
  /// ang Client/Loan Information, Payment Schedule, Payment History, Notes,
  /// at Download Receipt.
  void _openLoanDetails(BuildContext context, LoanModel loan) =>
      showLoanDetailsSidePanel(context, loanId: loan.id, loan: loan);

  void _openDetails(BuildContext context, String loanId) {
    // Full-page navigation — hindi na modal, para buong screen ang details
    // at may sariling URL (/hm/loan-applications/:id) na pwedeng i-refresh/share.
    context.push(
      RouteConstants.empLoanApplicationDetails.replaceFirst(':id', loanId),
    );
  }

  void _onActionDone() {
    // Silent refresh — hindi na naglo-load nang buo ang data table pagkatapos
    // ng approve / reject / cancel / assign rider.
    ref.read(hmLoanProvider.notifier).fetchLoans(silent: true);
  }

  // ───────────────────────── Loading / Empty / Pagination ─────────────────────────
  Widget _buildLoadingShimmer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          6,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.shimmerBase.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          height: 12,
                          decoration: BoxDecoration(
                              color:
                                  AppColors.shimmerBase.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 8),
                      Container(
                          height: 10,
                          width: 160,
                          decoration: BoxDecoration(
                              color:
                                  AppColors.shimmerHighlight.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(6))),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                    width: 86,
                    height: 28,
                    decoration: BoxDecoration(
                        color: AppColors.shimmerBase.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(20))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(HmLoanState state) {
    final isFiltered = state.search.isNotEmpty || state.tabFilter != 'all';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltered ? Icons.search_off_rounded : Icons.description_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'No matching applications' : 'No loan records',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () {
                _searchCtrl.clear();
                ref.read(hmLoanProvider.notifier).setSearch('');
                ref.read(hmLoanProvider.notifier).setTab('all');
              },
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPagination(HmLoanState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          const Spacer(),
          _PageBtn(
            icon: Icons.chevron_left_rounded,
            enabled: state.currentPage > 1,
            onTap: () => ref
                .read(hmLoanProvider.notifier)
                .fetchLoans(page: state.currentPage - 1),
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
            onTap: () => ref
                .read(hmLoanProvider.notifier)
                .fetchLoans(page: state.currentPage + 1),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Helpers ─────────────────────────
  String _timeAgo(DateTime d) {
    final diff = nowManila().difference(d);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  // ───────────────────────── Actions wiring ─────────────────────────
  Future<void> _showApprove(LoanModel loan) async {
    await showDialog(
      context: context,
      builder: (_) => ApproveRejectModal(
        loanId: loan.id,
        isApprove: true,
        onConfirm: (_, __, ___, ____) async {
          final ok =
              await ref.read(hmLoanProvider.notifier).approveLoan(loan.id);
          if (!mounted) return;
          Navigator.of(context).pop();
          context.showSnackBarAsToast(
            SnackBar(
              content:
                  Text(ok ? 'Loan approved successfully' : 'Approval failed'),
              backgroundColor: ok ? AppColors.success : AppColors.error,
            ),
          );
          if (ok) _onActionDone();
        },
      ),
    );
  }

  Future<void> _showReject(LoanModel loan) async {
    await showDialog(
      context: context,
      builder: (_) => ApproveRejectModal(
        loanId: loan.id,
        isApprove: false,
        onConfirm: (_, reason, reapplyAllowedAt, permanent) async {
          final ok = await ref.read(hmLoanProvider.notifier).rejectLoan(
                loan.id,
                reason ?? '',
                reapplyAllowedAt: reapplyAllowedAt,
                permanent: permanent,
              );
          if (!mounted) return;
          Navigator.of(context).pop();
          context.showSnackBarAsToast(
            SnackBar(
              content: Text(ok ? 'Loan rejected' : 'Reject failed'),
              backgroundColor: ok ? AppColors.error : AppColors.textSecondary,
            ),
          );
          if (ok) _onActionDone();
        },
      ),
    );
  }

  Future<void> _showAssignRider(LoanModel loan) async {
    final assigned = await showDialog<bool>(
      context: context,
      // Hindi pwedeng i-dismiss habang nagse-save — kung maisasara ito habang
      // in-flight ang assign, madi-dispose ang notifier at mag-throw ng
      // "Bad state: Tried to use HmCiNotifier after dispose was called."
      barrierDismissible: false,
      builder: (_) => CiAssignModal(loanId: loan.id),
    );
    if (assigned == true && mounted) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Rider assigned for credit investigation'),
          backgroundColor: AppColors.success,
        ),
      );
      _onActionDone();
    }
  }

  Future<void> _showAssignDisbursementRider(LoanModel loan) async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => RiderDisburseAssignModal(
        loanId: loan.id,
      ),
    );
    if (assigned == true && mounted) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Delivery rider assigned'),
          backgroundColor: AppColors.success,
        ),
      );
      _onActionDone();
    }
  }

  /// "Disburse in Office" — ibinibigay na sa lender ang cash sa opisina.
  ///
  /// Sa backend (`disbursements-delivery?fn=office-cash`): verified na
  /// `office_cash` disbursement ang nililikha, nagiging `active` ang loan, at
  /// nagsisimula ang payment schedule. May validation din doon (lahat ng
  /// Account Upgrade documents verified, walang existing disbursement) — ang
  /// error na iyon ang ipinapakita sa dialog kapag hindi natuloy.
  Future<void> _showDisburseOffice(LoanModel loan) async {
    final lenderName = (loan.lenderName ?? '').trim();
    final lender = lenderName.isEmpty ? 'the lender' : lenderName;
    final done = await showAsyncConfirmationDialog(
      context,
      title: 'Disburse in Office?',
      message:
          '${loan.principalAmount.toCurrency} in cash will be handed to $lender '
          '(${loan.loanNumber}) at the office.',
      confirmLabel: 'Disburse',
      confirmColor: AppColors.success,
      onConfirm: () async {
        try {
          await ref
              .read(hmDisbursementProvider.notifier)
              .disburseOfficeCash(loanId: loan.id);
          return null;
        } catch (e) {
          return ErrorHandler.handle(e).message;
        }
      },
    );
    if (done == true && mounted) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Cash released in office — loan is now active'),
          backgroundColor: AppColors.success,
        ),
      );
      _onActionDone();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting widgets
// ─────────────────────────────────────────────────────────────────────────────







class _FrequencyInline extends StatelessWidget {
  final String frequency;
  const _FrequencyInline({required this.frequency});

  @override
  Widget build(BuildContext context) {
    final f = frequency.toLowerCase();
    final Color c;
    final IconData icon;
    switch (f) {
      case 'daily':
        c = AppColors.riderGreen;
        icon = Icons.today_outlined;
        break;
      case 'weekly':
        c = AppColors.lenderBlue;
        icon = Icons.date_range_outlined;
        break;
      default:
        c = AppColors.deepNavy;
        icon = Icons.calendar_month_outlined;
    }
    // Flat inline — no square pill background/border
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Text(
          f.isEmpty ? '-' : '${f[0].toUpperCase()}${f.substring(1)}',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: c),
        ),
      ],
    );
  }
}

class _StatusInline extends StatelessWidget {
  final String status;

  /// Optional override — ginagamit ng In-Office table para ipakita ang TOTOONG
  /// progreso ng application (hal. 'Ongoing Loan', 'Upgraded Account') sa halip
  /// na ang hilaw na status nito ('converted', 'submitted').
  final String? labelOverride;
  final Color? colorOverride;

  const _StatusInline(
      {required this.status, this.labelOverride, this.colorOverride});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color c;
    String label;
    switch (s) {
      case 'pending':
        c = AppColors.warning;
        label = 'Pending CI';
        break;
      case 'under_review':
        c = AppColors.info;
        label = 'Under Review';
        break;
      case 'ci_required':
        c = AppColors.warning;
        label = 'CI Required';
        break;
      case 'ci_assigned':
        c = AppColors.lenderBlue;
        label = 'CI Assigned';
        break;
      case 'ci_completed':
        c = AppColors.deepNavy;
        label = 'CI Completed';
        break;
      case 'approved':
        c = AppColors.success;
        label = 'Approved';
        break;
      case 'rider_delivery_assigned':
        c = AppColors.goldDark;
        label = 'Pending Delivery';
        break;
      case 'rejected':
        c = AppColors.error;
        label = 'Rejected';
        break;
      case 'active':
        c = AppColors.riderGreen;
        // "Ongoing" ang label ng status na `active` (na-release at patuloy pa
        // ang bayad) — hiwalay ito sa "Ongoing Loan" na tab sa itaas.
        label = 'Ongoing';
        break;
      case 'completed':
        c = AppColors.info;
        label = 'Completed';
        break;
      case 'overdue':
        c = AppColors.error;
        label = 'Overdue';
        break;
      default:
        c = AppColors.textSecondary;
        label = s.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    }
    if (labelOverride != null) {
      label = labelOverride!;
      if (colorOverride != null) c = colorOverride!;
    }
    // Flat — dot + colored text, no square Container background/border
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: c),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RowActions extends StatelessWidget {
  final LoanModel loan;
  final VoidCallback onRefresh;
  const _RowActions({required this.loan, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    // Access to parent state for dialogs: use context.findAncestorStateOfType
    final parent =
        context.findAncestorStateOfType<_EmpLoanApplicationsScreenState>();
    final status = loan.status;
    // Overdue CI (latest CI failed/expired): allow reassignment even though
    // the loan is still 'ci_assigned'. Lender side stays "in progress".
    final ciFailed = loan.ciStatus == 'failed' ||
        loan.ciStatus == 'expired' ||
        loan.ciStatus == 'declined';
    final canAssignRider =
        ['pending', 'under_review', 'ci_required'].contains(status) ||
            (status == 'ci_assigned' && ciFailed);
    final canApprove = [
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    ].contains(status);
    final canAssignDeliveryRider = status == 'approved' &&
        !loan.riderDeliveryAssigned &&
        loan.disbursementMethod == 'rider_delivery';
    // Office pickup release — na-approve na (tapos na ang CI) pero hindi pa
    // naibibigay ang cash. Ito ang aksyon ng staff, at dating WALA ito sa menu
    // kaya "Open details" lang ang lumalabas kahit kailangan nang i-release.
    // `office_cash` = "Pick Up at Office" ang pinili ng lender; kung wala pang
    // pinipili (walang laman), pinapayagan pa rin ang release sa opisina.
    final method = (loan.disbursementMethod ?? '').toLowerCase().trim();
    final canDisburseOffice = status.toLowerCase().trim() == 'approved' &&
        loan.disbursedAt == null &&
        (method == 'office_cash' || method.isEmpty);
    final canReject = [
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    ].contains(status);

    // ORANGE indicator sa 3-dot: may KULANG pang aksyon ang staff.
    //  • Cash on Delivery: kailangan pang i-assign ang delivery rider — kaya
    //    DAPAT NAWAWALA na ang dot kapag may rider na
    //    (`rider_delivery_assigned` / `delivery_rider_name`). Dati, nananatili
    //    ang dot pagkatapos ng assignment dahil ang tanging basehan ay "may
    //    piniling method at hindi pa released".
    //  • Office pickup: nananatili hanggang ma-release ang cash
    //    (`disbursed_at`).
    // Realtime: naka-subscribe ang provider sa `loan_disbursement_preferences`
    // / `disbursements`, kaya agad itong nagre-refresh.
    final deliveryRiderAssigned = loan.riderDeliveryAssigned ||
        (loan.deliveryRiderName ?? '').trim().isNotEmpty;
    final disbursementChosen = status == 'approved' &&
        loan.disbursedAt == null &&
        (loan.disbursementMethod ?? '').isNotEmpty &&
        !(loan.disbursementMethod == 'rider_delivery' && deliveryRiderAssigned);

    // Compact: primary action + overflow menu
    final needsRiderDot =
        canAssignRider || canAssignDeliveryRider || disbursementChosen;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // View always visible
        _ActionIcon(
          icon: Icons.visibility_outlined,
          color: AppColors.deepNavy,
          tooltip: 'View details',
          onTap: () => parent?._openDetails(context, loan.id),
        ),
        const SizedBox(width: 6),
        // 3-dot menu with notification dot when rider needs assignment
        Stack(
          clipBehavior: Clip.none,
          children: [
            PopupMenuButton<String>(
              tooltip: 'Actions',
              offset: const Offset(0, 36),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              itemBuilder: (_) => [
                if (canApprove)
                  const PopupMenuItem(
                      value: 'approve',
                      child: Row(children: [
                        Icon(Icons.check_circle_outline,
                            size: 16, color: AppColors.success),
                        SizedBox(width: 8),
                        Text('Approve')
                      ])),
                if (canAssignRider)
                  PopupMenuItem(
                      value: 'assign_ci',
                      child: Row(children: [
                        const Icon(Icons.search_rounded,
                            size: 16, color: AppColors.info),
                        const SizedBox(width: 8),
                        Text(ciFailed ? 'Reassign CI Rider' : 'Assign CI Rider')
                      ])),
                if (canAssignDeliveryRider)
                  const PopupMenuItem(
                      value: 'assign_delivery',
                      child: Row(children: [
                        Icon(Icons.delivery_dining_rounded,
                            size: 16, color: AppColors.goldDark),
                        SizedBox(width: 8),
                        Text('Assign Cash on Delivery Rider')
                      ])),
                if (canDisburseOffice)
                  const PopupMenuItem(
                      value: 'disburse_office',
                      child: Row(children: [
                        Icon(Icons.storefront_rounded,
                            size: 16, color: AppColors.success),
                        SizedBox(width: 8),
                        Text('Disburse in Office')
                      ])),
                if (canReject)
                  const PopupMenuItem(
                      value: 'reject',
                      child: Row(children: [
                        Icon(Icons.cancel_outlined,
                            size: 16, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('Reject')
                      ])),
                const PopupMenuItem(
                    value: 'view',
                    child: Row(children: [
                      Icon(Icons.open_in_new_rounded,
                          size: 16, color: AppColors.textSecondary),
                      SizedBox(width: 8),
                      Text('Open details')
                    ])),
              ],
              onSelected: (v) {
                switch (v) {
                  case 'approve':
                    parent?._showApprove(loan);
                    break;
                  case 'reject':
                    parent?._showReject(loan);
                    break;
                  case 'assign_ci':
                    parent?._showAssignRider(loan);
                    break;
                  case 'assign_delivery':
                    parent?._showAssignDisbursementRider(loan);
                    break;
                  case 'disburse_office':
                    parent?._showDisburseOffice(loan);
                    break;
                  case 'view':
                    parent?._openDetails(context, loan.id);
                    break;
                }
              },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.more_horiz_rounded,
                    size: 16, color: AppColors.textSecondary),
              ),
            ),
            if (needsRiderDot)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Status label + kulay ng In-Office application — hindi ang hilaw na status
/// ng application ('submitted' / 'converted') kundi ang TOTOONG progreso nito
/// (kaparehong panuntunan ng label sa header ng `InOfficeWizard`):
///   • may naka-link nang loan → status ng LOAN ('Ongoing Loan',
///     'Loan Pending', 'Overdue Loan', …)
///   • 'submitted' (wala pang loan) → 'Upgraded Account'
///   • 'converted' (may loan na) → 'Converted to Loan'
(Color, String) _inOfficeStatusMeta(Map<String, dynamic> app) {
  final loan = app['loan'];
  if (loan is Map && loan.isNotEmpty) {
    final s = (loan['status'] ?? '').toString().toLowerCase().trim();
    return switch (s) {
      'active' => (AppColors.riderGreen, 'Ongoing Loan'),
      'overdue' => (AppColors.error, 'Overdue Loan'),
      'completed' => (AppColors.info, 'Completed Loan'),
      'approved' => (AppColors.success, 'Loan Approved'),
      'rejected' => (AppColors.error, 'Loan Rejected'),
      'cancelled' => (AppColors.error, 'Loan Cancelled'),
      'pending' || 'under_review' => (AppColors.warning, 'Loan Pending'),
      '' => (AppColors.textSecondary, 'Loan Application'),
      _ => (AppColors.textSecondary, 'Loan ${_titleCaseLabel(s)}'),
    };
  }
  return switch ((app['status'] ?? '').toString().toLowerCase().trim()) {
    'submitted' => (AppColors.info, 'Upgraded Account'),
    'converted' => (AppColors.deepNavy, 'Converted to Loan'),
    'draft' => (AppColors.textSecondary, 'Draft'),
    _ => (AppColors.textSecondary, 'Submitted'),
  };
}

String _titleCaseLabel(String s) => s
    .replaceAll('_', ' ')
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String _inOfficeLoanLabel(Map<String, dynamic> app) {
  final loan = app['loan'];
  if (loan is Map && loan.isNotEmpty) {
    final loanNumber = (loan['loan_number'] ?? '').toString();
    final loanStatus = (loan['status'] ?? '').toString();
    if (loanNumber.isNotEmpty) {
      return loanStatus.isNotEmpty
          ? '$loanNumber • $loanStatus'
          : loanNumber;
    }
  }
  return 'No loan yet';
}

class _InOfficeActions extends ConsumerWidget {
  final Map<String, dynamic> app;
  const _InOfficeActions({required this.app});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = app['id']?.toString() ?? '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionIcon(
          icon: Icons.visibility_outlined,
          color: AppColors.deepNavy,
          tooltip: 'View application',
          onTap: () => showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => InOfficeWizard(
              applicationId: id.isEmpty ? null : id,
              viewOnly: true,
              onComplete: () => ref.read(hmInOfficeProvider.notifier).load(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionIcon(
      {required this.icon,
      required this.color,
      required this.tooltip,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

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

class _Entrance extends StatefulWidget {
  final Widget child;
  const _Entrance({required this.child});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    final curved =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _offset = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(curved);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
