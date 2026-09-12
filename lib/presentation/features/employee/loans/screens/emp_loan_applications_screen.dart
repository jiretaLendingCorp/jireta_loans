// lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/filter_pill_tab.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../ci/widgets/emp_ci_assign_modal.dart';
import '../../../head_manager/loans/widgets/approve_reject_modal.dart';
import '../../../head_manager/disbursements/widgets/rider_disburse_assign_modal.dart';
import '../../../head_manager/in_office/widgets/in_office_wizard.dart';
import '../providers/emp_loan_provider.dart';
import '../../in_office/providers/emp_in_office_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class EmpLoanApplicationsScreen extends ConsumerStatefulWidget {
  const EmpLoanApplicationsScreen({super.key});

  @override
  ConsumerState<EmpLoanApplicationsScreen> createState() =>
      _EmpLoanApplicationsScreenState();
}class _EmpLoanApplicationsScreenState extends ConsumerState<EmpLoanApplicationsScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;
  final _scrollCtrl = ScrollController();
  // Keeps In-Office / Active Loan selected locally while staying on /employee/loans
  // so WebScaffold continues to highlight "Loan Records" in the side nav.
  String? _overrideTab;
  String _inOfficeSearch = '';

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
    FilterTabDef('in_office', 'In-Office Application', Icons.storefront_outlined),
  ];

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    ref.read(empLoanProvider.notifier).setDateRange(
          r == null ? null : SearchDateFilter.fromParam(r.start),
          r == null ? null : SearchDateFilter.toParam(r.end),
        );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loanState = ref.watch(empLoanProvider);
    final inOfficeAsync = ref.watch(empInOfficeProvider);
    final effectiveTab = _overrideTab ?? (loanState.statusFilter ?? 'all');
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
              _buildToolbar(loanState, inOfficeAsync, isInOffice),
              if (isInOffice) ...[
                _buildInOfficeSection(inOfficeAsync),
              ] else ...[
                if (loanState.isLoading)
                  _buildShimmer()
                else if (loanState.loans.isEmpty)
                  _buildEmpty()
                else
                  _buildTable(loanState.loans),
              ],
              // Pagination bar — palaging nakikita kahit isang page lang.
              if (!isInOffice) ...[
                const SizedBox(height: 16),
                _buildPagination(loanState),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Pill Tabs + Dropdown ─────────────────────────
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
        final statusKey = v == 'all' ? null : v;
        ref.read(empLoanProvider.notifier).setStatus(statusKey);
      },
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
                ref.read(empInOfficeProvider.notifier).loadList();
                return;
              }
              if (_overrideTab != null) setState(() => _overrideTab = null);
              final statusKey = t.key == 'all' ? null : t.key;
              // For 'active' pill, statusKey is 'active' not null, handle specifically
              if (t.key == 'active') {
                ref.read(empLoanProvider.notifier).setStatus('active');
              } else {
                ref.read(empLoanProvider.notifier).setStatus(statusKey);
              }
            },
          ),
        );
      }).toList(),
    );
  }

  // ───────────────────────── Toolbar (simple, gaya ng Head Manager) ─────────────────────────
  Widget _buildToolbar(EmpLoanState loanState,
      AsyncValue<Map<String, dynamic>> inOfficeAsync, bool isInOffice) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.border),
          left: BorderSide(color: AppColors.border),
          right: BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: ResponsiveSearchToolbar(
        searchField: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search loan applications...',
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
            } else {
              ref.read(empLoanProvider.notifier).setSearch(v);
            }
          },
        ),
        trailing: [
          SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
          SearchResultsChip(
            count: isInOffice
                ? _filteredEmpInOffice(
                        (inOfficeAsync.valueOrNull?['items'] as List?) ?? [])
                    .length
                : loanState.total,
          ),
        ],
      ),
    );
  }

  List _filteredEmpInOffice(List items) {
    if (_inOfficeSearch.isEmpty) return items;
    final q = _inOfficeSearch.toLowerCase();
    return items.where((e) {
      final m = e as Map<String, dynamic>;
      final name = (m['lender_name'] ?? '').toString().toLowerCase();
      final id = (m['id'] ?? '').toString().toLowerCase();
      return name.contains(q) || id.contains(q);
    }).toList();
  }

  // ───────────────────────── In-Office embedded ─────────────────────────
  Widget _buildInOfficeSection(
      AsyncValue<Map<String, dynamic>> async) {
    if (async.isLoading) return _buildShimmer();
    final rawItems = (async.valueOrNull?['items'] as List?) ?? [];
    final items = _filteredEmpInOffice(rawItems);
    if (items.isEmpty) return _buildInOfficeEmpty(rawItems.isEmpty);
    return _buildInOfficeList(items);
  }

  Widget _buildInOfficeList(List items) {
    return ResponsiveListCard(
      minTableWidth: 860,
      radius: 0,
      columns: const [
        ResponsiveCol('Lender', icon: Icons.person_outline, flex: 3),
        ResponsiveCol('Loan', icon: Icons.request_quote_outlined, flex: 2),
        ResponsiveCol('Created', icon: Icons.event_outlined, flex: 2),
        ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 2),
      ],
      actionsCol: ResponsiveActionsCol(
        label: '',
        width: 140,
        alignment: Alignment.centerRight,
        headerWidget: ElevatedButton.icon(
          onPressed: () => showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => InOfficeWizard(
              applicationId: null,
              onComplete: () =>
                  ref.read(empInOfficeProvider.notifier).loadList(),
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
      rows: items.map((e) {
        final m = e as Map<String, dynamic>;
        return ResponsiveRow(
          cells: [
            Text(
              (m['lender_name'] ?? 'Walk-in Lender').toString(),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _empInOfficeLoanLabel(m),
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600),
            ),
            Text(
              (() {
                final raw = (m['created_at'] ?? '').toString();
                return raw.length >= 10 ? raw.substring(0, 10) : raw;
              })(),
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600),
            ),
            _EmpStatusInline(
                status: (m['status'] ?? 'submitted').toString()),
          ],
          actions: _EmpInOfficeActions(
              appId: (m['id'] ?? '').toString()),
        );
      }).toList(),
    );
  }

  Widget _buildInOfficeEmpty(bool isTrulyEmpty) {
    final isFiltered = _inOfficeSearch.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.border),
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
                        ref.read(empInOfficeProvider.notifier).loadList(),
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

  Widget _buildTable(List<LoanModel> loans) {
    return ResponsiveListCard(
      minTableWidth: 920,
      radius: 0,
      variant: ResponsiveListVariant.card,
      columns: const [
        ResponsiveCol('Loan #', flex: 3),
        ResponsiveCol('Lender', flex: 3),
        ResponsiveCol('Amount', flex: 2),
        ResponsiveCol('Frequency', flex: 2),
        ResponsiveCol('Status', flex: 2),
        ResponsiveCol('Applied', flex: 2),
      ],
      actionsCol: const ResponsiveActionsCol(label: 'Actions', width: 96),
      rows: loans.map((loan) => _buildTableRow(loan)).toList(),
    );
  }

  ResponsiveRow _buildTableRow(LoanModel loan) {
    return ResponsiveRow(
      onTap: () => _openDetails(context, loan.id),
      cells: [
        Text(
          loan.loanNumber,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AppColors.deepNavy,
          ),
        ),
        Text(
          loan.lenderName ?? '—',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Text(
          '₱${loan.principalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _EmpFrequencyInline(frequency: loan.frequency),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _EmpStatusInline(status: loan.displayStatus),
            ),
          if (loan.ciStatus != null &&
              (loan.ciStatus == 'assigned' ||
                  loan.ciStatus == 'accepted' ||
                  loan.ciStatus == 'in_progress') &&
              loan.status == 'ci_assigned') ...[
            const SizedBox(height: 4),
            Text(
              loan.assignedRiderName != null
                  ? 'Rider: ${loan.assignedRiderName}'
                  : 'Rider Assigned',
              textAlign: TextAlign.start,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.riderGreen,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // Overdue CI: failed task needs a new rider.
          if (loan.ciStatus != null &&
              (loan.ciStatus == 'failed' ||
                  loan.ciStatus == 'expired') &&
              loan.status == 'ci_assigned') ...[
            const SizedBox(height: 4),
            const Text(
              'CI overdue — reassignment needed',
              textAlign: TextAlign.start,
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${loan.createdAt.year}-${loan.createdAt.month.toString().padLeft(2, '0')}-${loan.createdAt.day.toString().padLeft(2, '0')}',
            textAlign: TextAlign.start,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
      actions: _buildActions(loan),
    );
  }

  Widget _buildActions(LoanModel loan) {
    // Normalize para kahit 'Pending' / 'PENDING' / may whitespace ay match —
    // gaya ng Head Manager logic (pending => Assign Rider visible).
    final status = loan.status.toLowerCase().trim();
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
    final canReject = [
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    ].contains(status);

    // Identical sa Head Manager: View icon + 3 dots (PopupMenu)
    final needsRiderDot = canAssignRider || canAssignDeliveryRider;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionIcon(
          icon: Icons.visibility_outlined,
          color: AppColors.deepNavy,
          tooltip: 'View details',
          onTap: () => _openDetails(context, loan.id),
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
                    _showApprove(loan);
                    break;
                  case 'reject':
                    _showReject(loan);
                    break;
                  case 'assign_ci':
                    _showAssignRider(loan);
                    break;
                  case 'assign_delivery':
                    _showAssignDeliveryRider(loan);
                    break;
                  case 'view':
                    _openDetails(context, loan.id);
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

  void _openDetails(BuildContext context, String loanId) {
    // Full-page navigation — hindi na modal.
    context.push(
      RouteConstants.empLoanApplicationDetails.replaceFirst(':id', loanId),
    );
  }

  Future<void> _showApprove(LoanModel loan) async {
    await showDialog(
      context: context,
      builder: (_) => ApproveRejectModal(
        loanId: loan.id,
        isApprove: true,
        onConfirm: (_, __) async {
          final ok = await ref.read(empLoanProvider.notifier).approve(loan.id);
          if (!mounted) return;
          Navigator.of(context).pop();
          context.showSnackBarAsToast(
            SnackBar(
              content:
                  Text(ok ? 'Loan approved successfully' : 'Approval failed'),
              backgroundColor: ok ? AppColors.success : AppColors.error,
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAssignRider(LoanModel loan) async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => EmpCiAssignModal(loanId: loan.id, ciId: ''),
    );
    if (assigned == true && mounted) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Rider assigned for credit investigation'),
          backgroundColor: AppColors.success,
        ),
      );
      ref.read(empLoanProvider.notifier).load();
    }
  }

  Future<void> _showAssignDeliveryRider(LoanModel loan) async {
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
      ref.read(empLoanProvider.notifier).load();
    }
  }

  Future<void> _showReject(LoanModel loan) async {
    await showDialog(
      context: context,
      builder: (_) => ApproveRejectModal(
        loanId: loan.id,
        isApprove: false,
        onConfirm: (_, reason) async {
          if (!mounted) return;
          final notifier = ref.read(empLoanProvider.notifier);
          final ok = await notifier.reject(loan.id, reason ?? '');
          if (!mounted) return;
          Navigator.of(context).pop();
          context.showSnackBarAsToast(
            SnackBar(
              content: Text(ok ? 'Loan rejected' : 'Reject failed'),
              backgroundColor: ok ? AppColors.error : AppColors.textSecondary,
            ),
          );
        },
      ),
    );
  }

  Widget _buildPagination(EmpLoanState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Text(
            'Page ${state.page} of ${state.totalPages}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
          const Spacer(),
          _EmpPageBtn(
            icon: Icons.chevron_left_rounded,
            enabled: state.page > 1,
            onTap: () => ref.read(empLoanProvider.notifier).setPage(state.page - 1),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${state.page} / ${state.totalPages}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          _EmpPageBtn(
            icon: Icons.chevron_right_rounded,
            enabled: state.page < state.totalPages,
            onTap: () => ref.read(empLoanProvider.notifier).setPage(state.page + 1),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    // Use a full-width card matching the HM style so the empty state is
    // visible inside the SingleChildScrollView (Center alone collapses and
    // has unbounded height inside the outer scroll).
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.border),
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
              Icons.description_outlined,
              size: 32,
              color: AppColors.deepNavy.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No loan applications found',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'New lender applications will appear here once submitted.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // Shimmer that is safe inside SingleChildScrollView — uses Column instead of
  // ListView (ListView inside a scroll view gets unbounded height and throws
  // "Vertical viewport was given unbounded height").
  Widget _buildShimmer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
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
                              color: AppColors.shimmerHighlight
                                  .withValues(alpha: 0.9),
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
}




class _EmpInOfficeActions extends ConsumerWidget {
  final String appId;
  const _EmpInOfficeActions({required this.appId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              applicationId: appId.isEmpty ? null : appId,
              viewOnly: true,
              onComplete: () =>
                  ref.read(empInOfficeProvider.notifier).loadList(),
            ),
          ),
        ),
      ],
    );
  }
}

String _empInOfficeLoanLabel(Map<String, dynamic> m) {
  final loan = m['loan'];
  if (loan is Map && loan.isNotEmpty) {
    final loanNumber = (loan['loan_number'] ?? '').toString();
    final loanStatus = (loan['status'] ?? '').toString();
    if (loanNumber.isNotEmpty) {
      return loanStatus.isNotEmpty ? '$loanNumber • $loanStatus' : loanNumber;
    }
  }
  return 'No loan yet';
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

class _EmpFrequencyInline extends StatelessWidget {
  final String frequency;
  const _EmpFrequencyInline({required this.frequency});

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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Text(
          f.isEmpty ? '-' : '${f[0].toUpperCase()}${f.substring(1)}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c),
        ),
      ],
    );
  }
}

class _EmpStatusInline extends StatelessWidget {
  final String status;
  const _EmpStatusInline({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final Color c;
    final String label;
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _EmpPageBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _EmpPageBtn(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: enabled ? AppColors.borderDark : AppColors.border),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
        ),
      ),
    );
  }
}
