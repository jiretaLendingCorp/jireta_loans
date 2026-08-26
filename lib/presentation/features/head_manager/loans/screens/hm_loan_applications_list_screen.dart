// lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../ci/widgets/ci_assign_modal.dart';
import '../../disbursements/widgets/rider_disburse_assign_modal.dart';
import '../providers/hm_loan_provider.dart';
import '../widgets/approve_reject_modal.dart';
import '../widgets/loan_application_details_modal.dart';
import '../../in_office/providers/hm_in_office_provider.dart';
import '../../in_office/widgets/in_office_wizard.dart';
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
  final _scrollCtrl = ScrollController();
  // Keeps In-Office selected locally while staying on /hm/loan-applications
  // so WebScaffold continues to highlight "Loan Records" in the side nav.
  String? _overrideTab;
  String _inOfficeSearch = '';

  final _tabs = const [
    _TabDef('all', 'All', Icons.layers_outlined),
    _TabDef('pending', 'Pending', Icons.hourglass_top_rounded),
    _TabDef('under_review', 'Under Review', Icons.rate_review_outlined),
    _TabDef('ci_required', 'CI Required', Icons.search_outlined),
    _TabDef('ci_assigned', 'CI Assigned', Icons.assignment_ind_outlined),
    _TabDef('ci_completed', 'CI Completed', Icons.verified_outlined),
    _TabDef('active', 'Active Loan', Icons.account_balance_wallet_outlined),
    _TabDef('in_office', 'In-Office Application', Icons.storefront_outlined),
  ];

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
    final effectiveTab = _overrideTab ?? loanState.tabFilter;
    final isInOffice = effectiveTab == 'in_office';

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
              _buildToolbar(loanState, inOfficeState, isInOffice),
              const SizedBox(height: 16),
              if (isInOffice) ...[
                _buildInOfficeSection(inOfficeState),
              ] else ...[
                if (loanState.isLoading)
                  _buildLoadingShimmer()
                else if (loanState.loans.isEmpty)
                  _buildEmpty(loanState)
                else
                  _Entrance(
                    child: _buildPremiumTable(loanState.loans),
                  ),
                if (loanState.totalPages > 1) ...[
                  const SizedBox(height: 16),
                  _buildPagination(loanState),
                ],
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────── Pill Tabs ───────────────────────────────
  // All pills stay on /hm/loan-applications so the side-nav highlights
  // "Loan Records" for Active Loan & In-Office as requested.
  Widget _buildTabPills(String active) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _tabs.map((t) {
          final isActive = t.key == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _PillTab(
              def: t,
              active: isActive,
              onTap: () {
                if (t.key == 'in_office') {
                  setState(() => _overrideTab = 'in_office');
                  // Ensure in-office data is fresh when tab is first opened.
                  // ignore: unused_result
                  ref.read(hmInOfficeProvider.notifier).load();
                  return;
                }
                // For Active Loan and the pipeline tabs, use the loans provider.
                // Clear in-office override so we return to loan table view.
                if (_overrideTab != null) {
                  setState(() => _overrideTab = null);
                }
                ref.read(hmLoanProvider.notifier).setTab(t.key);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────── Toolbar ───────────────────────────────
  // No inner box — single outer container with flat Search field (hint "Search").
  Widget _buildToolbar(
      HmLoanState loanState, HmInOfficeState inOfficeState, bool isInOffice) {
    final hasSearch =
        isInOffice ? _inOfficeSearch.isNotEmpty : loanState.search.isNotEmpty;
    final resultsCount = isInOffice
        ? _filteredInOffice(inOfficeState.applications).length
        : loanState.loans.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded,
              size: 18,
              color:
                  hasSearch ? AppColors.deepNavy : AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                if (isInOffice) {
                  setState(() => _inOfficeSearch = v);
                } else {
                  ref.read(hmLoanProvider.notifier).setSearch(v);
                }
              },
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(
                    fontSize: 13, color: AppColors.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (hasSearch)
            InkWell(
              onTap: () {
                _searchCtrl.clear();
                if (isInOffice) {
                  setState(() => _inOfficeSearch = '');
                } else {
                  ref.read(hmLoanProvider.notifier).setSearch('');
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: AppColors.textSecondary),
              ),
            ),
          if (hasSearch) const SizedBox(width: 10),
          _ToolbarIcon(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: () => isInOffice
                ? ref.read(hmInOfficeProvider.notifier).load()
                : ref.read(hmLoanProvider.notifier).fetchLoans(),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers_outlined,
                    size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  '$resultsCount results',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredInOffice(
      List<Map<String, dynamic>> apps) {
    if (_inOfficeSearch.isEmpty) return apps;
    final q = _inOfficeSearch.toLowerCase();
    return apps.where((a) {
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

  Widget _buildInOfficeList(List<Map<String, dynamic>> apps) {
    return Container(
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
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FB),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Expanded(
                    flex: 3,
                    child: _HLabel('Lender', Icons.person_outline)),
                const Expanded(
                    flex: 2, child: _HLabel('Step', Icons.layers_outlined)),
                const Expanded(
                    flex: 2, child: _HLabel('Created', Icons.event_outlined)),
                const Expanded(
                    flex: 2, child: _HLabel('Status', Icons.flag_outlined)),
                SizedBox(
                  width: 140,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
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
                  ),
                ),
              ],
            ),
          ),
          ...apps.asMap().entries.map((e) {
            final idx = e.key;
            final app = e.value;
            final isEven = idx.isEven;
            final createdAt = app['created_at'] != null
                ? DateTime.tryParse(app['created_at'].toString())
                : null;
            final dateStr = createdAt != null
                ? DateFormat('MMM dd, yyyy').format(createdAt)
                : '—';
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isEven ? Colors.white : const Color(0xFFFDFDFD),
                border:
                    const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      (app['lender_name'] ?? 'Walk-in Lender').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Step ${app['wizard_step'] ?? 1} of 5',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      dateStr,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _StatusInline(
                        status: (app['status'] ?? 'submitted').toString()),
                  ),
                  SizedBox(
                    width: 140,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _InOfficeActions(app: app),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
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
    final dateFmt = DateFormat('MMM dd, yyyy');

    return Container(
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
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FB),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 3,
                    child: _HLabel('Lender & Loan', Icons.person_outline)),
                Expanded(
                    flex: 2,
                    child: _HLabel('Amount', Icons.payments_outlined)),
                Expanded(
                    flex: 2,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: _HLabel('Frequency', Icons.repeat_rounded))),
                Expanded(
                    flex: 2,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: _HLabel('Applied', Icons.event_outlined))),
                Expanded(
                    flex: 3,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: _HLabel('Status', Icons.flag_outlined))),
                SizedBox(width: 96, child: _HLabel('Action', Icons.bolt_outlined)),
              ],
            ),
          ),
          // Rows
          ...loans.asMap().entries.map((entry) {
            final idx = entry.key;
            final loan = entry.value;
            final isEven = idx.isEven;
            final status = loan.displayStatus;
            final lenderName =
                '${loan.lenderFirstName} ${loan.lenderLastName}'.trim().isEmpty
                    ? (loan.lenderName ?? '—')
                    : '${loan.lenderFirstName} ${loan.lenderLastName}'.trim();

            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isEven ? Colors.white : const Color(0xFFFDFDFD),
                border: const Border(
                    bottom: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              child: Row(
                children: [
                    // Lender & Loan
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lenderName.isEmpty ? '—' : lenderName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.deepNavy
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  loan.loanNumber,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.deepNavy),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  loan.createdAt
                                      .toIso8601String()
                                      .substring(0, 10),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textTertiary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Amount
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₱${fmt.format(loan.principalAmount)}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${loan.termLabel} • ${loan.installmentAmount > 0 ? "₱${fmt.format(loan.installmentAmount)}/ ${loan.termUnit.replaceAll('s', '')}" : loan.paymentFrequency}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Frequency — flat inline, start-aligned pantay sa header
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _FrequencyInline(frequency: loan.paymentFrequency),
                      ),
                    ),
                    // Applied date — start-aligned pantay sa header
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateFmt.format(loan.createdAt),
                            textAlign: TextAlign.start,
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
                    ),
                    // Status — flat inline dot + text, start-aligned pantay sa header
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _StatusInline(status: status),
                          ),
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
                        ],
                      ),
                    ),
                    // Action — left-aligned pantay sa header
                    SizedBox(
                      width: 96,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _RowActions(loan: loan, onRefresh: _onActionDone),
                      ),
                    ),
                  ],
                ),
              );
          }),
        ],
      ),
    );
  }

  void _onActionDone() {
    ref.read(hmLoanProvider.notifier).fetchLoans();
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
              isFiltered ? Icons.search_off_rounded : Icons.description_outlined,
              size: 32,
              color: AppColors.deepNavy.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'No matching applications' : 'No loan applications',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            isFiltered
                ? 'Try adjusting your search or switch to a different pipeline stage.'
                : 'New lender applications will appear here once submitted.',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    _searchCtrl.clear();
                    ref.read(hmLoanProvider.notifier).setSearch('');
                    ref.read(hmLoanProvider.notifier).setTab('all');
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('Clear filters'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () =>
                      ref.read(hmLoanProvider.notifier).fetchLoans(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.deepNavy,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPagination(HmLoanState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
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
    final diff = DateTime.now().difference(d);
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
        loanAmount: loan.principalAmount,
        lenderName: loan.lenderName ?? 'Lender',
        lenderAddress: loan.formattedLenderAddress,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TabDef {
  final String key;
  final String label;
  final IconData icon;
  const _TabDef(this.key, this.label, this.icon);
}

class _PillTab extends StatelessWidget {
  final _TabDef def;
  final bool active;
  final VoidCallback onTap;
  const _PillTab({required this.def, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.deepNavy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? AppColors.deepNavy : AppColors.border,
              width: active ? 1.2 : 1),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.deepNavy.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(def.icon,
                size: 14,
                color: active ? AppColors.gold : AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(
              def.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}





class _HLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  const _HLabel(this.text, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

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
  const _StatusInline({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final Color c;
    final String label;
    switch (s) {
      case 'pending':
        c = AppColors.warning;
        label = 'Pending';
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

class _ToolbarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ToolbarIcon(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 16, color: AppColors.textSecondary),
        ),
      ),
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
    final canAssignRider =
        ['pending', 'under_review', 'ci_required'].contains(status);
    final canApprove = [
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    ].contains(status);
    final canAssignDeliveryRider =
        status == 'approved' && loan.disbursementMethod == 'rider_delivery';
    final canReject = [
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    ].contains(status);

    // Compact: primary action + overflow menu
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // View always visible
        _ActionIcon(
          icon: Icons.visibility_outlined,
          color: AppColors.deepNavy,
          tooltip: 'View details',
          onTap: () => showLoanApplicationDetailsModal(context, loan.id),
        ),
        const SizedBox(width: 6),
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
              const PopupMenuItem(
                  value: 'assign_ci',
                  child: Row(children: [
                    Icon(Icons.search_rounded,
                        size: 16, color: AppColors.info),
                    SizedBox(width: 8),
                    Text('Assign CI Rider')
                  ])),
            if (canAssignDeliveryRider)
              const PopupMenuItem(
                  value: 'assign_delivery',
                  child: Row(children: [
                    Icon(Icons.delivery_dining_rounded,
                        size: 16, color: AppColors.goldDark),
                    SizedBox(width: 8),
                    Text('Assign Delivery Rider')
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
              case 'view':
                showLoanApplicationDetailsModal(context, loan.id);
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
      ],
    );
  }
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
          tooltip: 'Continue application',
          onTap: () => showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => InOfficeWizard(
              applicationId: id.isEmpty ? null : id,
              onComplete: () => ref.read(hmInOfficeProvider.notifier).load(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _ActionIcon(
          icon: Icons.edit_outlined,
          color: AppColors.info,
          tooltip: 'Resume wizard',
          onTap: () => showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => InOfficeWizard(
              applicationId: id.isEmpty ? null : id,
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
