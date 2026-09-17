// lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart
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
import '../../ci/widgets/ci_assign_modal.dart';
import '../../disbursements/widgets/rider_disburse_assign_modal.dart';
import '../../disbursements/screens/hm_disbursement_details_screen.dart';
import '../providers/hm_loan_provider.dart';
import '../widgets/approve_reject_modal.dart';
import '../../in_office/providers/hm_in_office_provider.dart';
import '../../in_office/widgets/in_office_wizard.dart';
import '../../disbursements/providers/hm_disbursement_provider.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../../core/errors/error_handler.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class HmLoanApplicationsListScreen extends ConsumerStatefulWidget {
  const HmLoanApplicationsListScreen({super.key});

  @override
  ConsumerState<HmLoanApplicationsListScreen> createState() =>
      _HmLoanApplicationsListScreenState();
}

class _HmLoanApplicationsListScreenState
    extends ConsumerState<HmLoanApplicationsListScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;
  final _scrollCtrl = ScrollController();
  // Keeps In-Office selected locally while staying on /hm/loan-applications
  // so WebScaffold continues to highlight "Loan Records" in the side nav.
  String? _overrideTab;
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
    FilterTabDef('active', 'Active Loan', Icons.account_balance_wallet_outlined),
    FilterTabDef('completed', 'Completed', Icons.verified_rounded),
    FilterTabDef('in_office', 'In-Office Application', Icons.storefront_outlined),
    FilterTabDef('disbursements', 'Disbursements', Icons.payments_outlined),
  ];

  /// Manila-day bounds ng napiling filter — `null` kapag walang date filter.
  String? get _dateFromParam =>
      _dateRange == null ? null : SearchDateFilter.fromParam(_dateRange!.start);
  String? get _dateToParam =>
      _dateRange == null ? null : SearchDateFilter.toParam(_dateRange!.end);

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    final from = _dateFromParam;
    final to = _dateToParam;
    // Naka-wire sa KASALUKUYANG tab: dati, ang loan list lang ang tumatanggap ng
    // date range kaya WALANG nangyayari sa In-Office at Disbursements tabs
    // kahit may napiling petsa. Sinasabayan pa rin ang loan list para hindi
    // stale ang pipeline/active/completed kapag lumipat pabalik.
    ref.read(hmLoanProvider.notifier).setDateRange(from, to);
    if (_overrideTab == 'in_office') {
      ref.read(hmInOfficeProvider.notifier).setDateRange(from, to);
    } else if (_overrideTab == 'disbursements') {
      ref.read(hmDisbursementProvider.notifier).setDateRange(from, to);
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
    final effectiveTab = _overrideTab ?? loanState.tabFilter;
    final isInOffice = effectiveTab == 'in_office';
    final isDisbursements = effectiveTab == 'disbursements';

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
              _buildToolbar(loanState, inOfficeState, disbState,
                  isInOffice, isDisbursements),
              const SizedBox(height: 16),
              if (isInOffice) ...[
                _buildInOfficeSection(inOfficeState),
              ] else if (isDisbursements) ...[
                _buildDisbursementSection(disbState),
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
  // Active Loan & In-Office stay as pills; pipeline (All/Pending/etc.) is dropdown.
  Widget _buildTabPills(String active) {
    final dropdownKeys = _dropdownTabs.map((e) => e.key).toSet();
    final isDropdownActive = dropdownKeys.contains(active);
    final dropdownValue = isDropdownActive ? active : null;

    return FilterTabBar(
      dropdownLabel: 'Pipeline',
      dropdownOptions: _dropdownTabs,
      dropdownValue: dropdownValue,
      onDropdownChanged: (v) {
        if (_overrideTab != null) setState(() => _overrideTab = null);
        ref.read(hmLoanProvider.notifier).setTab(v);
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
              if (t.key == 'in_office') {
                setState(() => _overrideTab = 'in_office');
                // Isinasama ang date filter ng screen (ito ang source of truth)
                // para kapag pinili ang range habang nasa ibang tab, tama pa
                // rin ang mga lalabas na application.
                ref
                    .read(hmInOfficeProvider.notifier)
                    .setDateRange(_dateFromParam, _dateToParam);
                return;
              }
              if (t.key == 'disbursements') {
                setState(() => _overrideTab = 'disbursements');
                ref
                    .read(hmDisbursementProvider.notifier)
                    .setDateRange(_dateFromParam, _dateToParam);
                return;
              }
              if (_overrideTab != null) setState(() => _overrideTab = null);
              ref.read(hmLoanProvider.notifier).setTab(t.key);
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
      bool isInOffice,
      bool isDisbursements) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ResponsiveSearchToolbar(
          searchField: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: isDisbursements
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
        // progreso: 'Active Loan' kapag aktibo na ang naka-link na loan, at
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
            // Outstanding balance — para lang sa CURRENT ACTIVE LOAN;
            // "N/A" kapag hindi ito ang kasalukuyang aktibong loan.
            Text(
              isCurrentActiveLoan
                  ? '₱${fmt.format(loan.outstandingBalance)}'
                  : 'N/A',
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

  void _openDetails(BuildContext context, String loanId) {
    // Full-page navigation — hindi na modal, para buong screen ang details
    // at may sariling URL (/hm/loan-applications/:id) na pwedeng i-refresh/share.
    context.push(
      RouteConstants.hmLoanApplicationDetails.replaceFirst(':id', loanId),
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
        onConfirm: (_, __) async {
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
        onConfirm: (_, reason) async {
          final ok = await ref
              .read(hmLoanProvider.notifier)
              .rejectLoan(loan.id, reason ?? '');
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
      message: 'Ibibigay na ang ${loan.principalAmount.toCurrency} cash kay $lender '
          '(${loan.loanNumber}) sa opisina.\n\nKapag na-disburse: magiging '
          'Active na ang loan at magsisimula ang payment schedule — kaya '
          'siguraduhing natanggap na ng lender ang pera bago i-confirm.',
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
  /// progreso ng application (hal. 'Active Loan', 'Upgraded Account') sa halip
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
        label = 'Active';
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
        context.findAncestorStateOfType<_HmLoanApplicationsListScreenState>();
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
///   • may naka-link nang loan → status ng LOAN ('Active Loan',
///     'Loan Pending', 'Overdue Loan', …)
///   • 'submitted' (wala pang loan) → 'Upgraded Account'
///   • 'converted' (may loan na) → 'Converted to Loan'
(Color, String) _inOfficeStatusMeta(Map<String, dynamic> app) {
  final loan = app['loan'];
  if (loan is Map && loan.isNotEmpty) {
    final s = (loan['status'] ?? '').toString().toLowerCase().trim();
    return switch (s) {
      'active' => (AppColors.riderGreen, 'Active Loan'),
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
