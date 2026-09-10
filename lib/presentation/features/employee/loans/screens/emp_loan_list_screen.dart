// lib/presentation/features/employee/loans/screens/emp_loan_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../../head_manager/loans/providers/hm_loan_provider.dart';
import '../providers/emp_active_loan_provider.dart';
import '../widgets/emp_loan_details_modal.dart';

class EmpLoanListScreen extends ConsumerStatefulWidget {
  const EmpLoanListScreen({super.key});

  @override
  ConsumerState<EmpLoanListScreen> createState() => _EmpLoanListScreenState();
}

class _EmpLoanListScreenState extends ConsumerState<EmpLoanListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;
  final _tabs = [
    ('active', 'Active'),
    ('completed', 'Completed'),
    ('overdue', 'Overdue'),
    ('all', 'All History'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    ref
        .read(empActiveLoanProvider.notifier)
        .setTab(_tabs[_tabController.index].$1);
  }

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    ref.read(empActiveLoanProvider.notifier).setDateRange(
          r == null ? null : SearchDateFilter.fromParam(r.start),
          r == null ? null : SearchDateFilter.toParam(r.end),
        );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empActiveLoanProvider);
    return WebScaffold(
      title: 'Active Loans',
      body: Column(
        children: [
          _buildTabBar(),
          _buildFilters(state),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.loans.isEmpty
                    ? _buildEmpty()
                    : _buildTable(state.loans),
          ),
          // Pagination bar — palaging nakikita kahit isang page lang.
          _buildPagination(state),
        ],
      ),
    );
  }

  Widget _buildTabBar() => Container(
        color: Colors.white,
        child: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.deepNavy,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.gold,
          tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
        ),
      );

  Widget _buildFilters(HmLoanState state) => Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: ResponsiveSearchToolbar(
          searchField: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by loan # or lender name...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) =>
                ref.read(empActiveLoanProvider.notifier).setSearch(v),
          ),
          trailing: [
            SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
            SearchResultsChip(count: state.loans.length),
          ],
        ),
      );

  Widget _buildTable(List<LoanModel> loans) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ResponsiveListCard(
        minTableWidth: 860,
        variant: ResponsiveListVariant.card,
        headerTextStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: AppColors.textSecondary),
        columns: const [
          ResponsiveCol('LOAN #', flex: 2),
          ResponsiveCol('LENDER', flex: 3),
          ResponsiveCol('PRINCIPAL', flex: 2),
          ResponsiveCol('OUTSTANDING', flex: 2),
          ResponsiveCol('DUE DATE', flex: 2),
          ResponsiveCol('STATUS', flex: 2),
        ],
        actionsCol: const ResponsiveActionsCol(label: '', flex: 1),
        rows: loans.map((loan) => _buildRow(loan, fmt)).toList(),
      ),
    );
  }

  ResponsiveRow _buildRow(LoanModel loan, NumberFormat fmt) {
    final color = _statusColor(loan.displayStatus);
    return ResponsiveRow(
      onTap: () => showEmpLoanDetailsModal(context, loan.id),
      cells: [
        Text(loan.loanNumber,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        Text(loan.lenderName ?? '-',
            style: const TextStyle(fontSize: 13)),
        Text('₱${fmt.format(loan.principalAmount)}',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500)),
        Text(
          '₱${fmt.format(loan.outstandingBalance)}',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: loan.status == 'overdue'
                  ? AppColors.error
                  : AppColors.textPrimary),
        ),
        Text(
          loan.dueDate != null
              ? DateFormat('MMM dd, yyyy').format(loan.dueDate!)
              : '-',
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4)),
          child: Text(
            loan.displayStatus
                .replaceAll('_', ' ')
                .split(' ')
                .map((w) => w.isEmpty
                    ? w
                    : '${w[0].toUpperCase()}${w.substring(1)}')
                .join(' '),
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
        ),
      ],
      actions: _ActionCell(
          loan: loan,
          onTap: () => showEmpLoanDetailsModal(context, loan.id)),
    );
  }

  Widget _buildEmpty() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text('No loans found',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          ],
        ),
      );

  Widget _buildPagination(HmLoanState state) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: state.currentPage > 1
                  ? () => ref
                      .read(empActiveLoanProvider.notifier)
                      .fetchLoans(page: state.currentPage - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Page ${state.currentPage} of ${state.totalPages}',
                style: const TextStyle(fontSize: 14)),
            IconButton(
              onPressed: state.currentPage < state.totalPages
                  ? () => ref
                      .read(empActiveLoanProvider.notifier)
                      .fetchLoans(page: state.currentPage + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );

  Color _statusColor(String status) {
    switch (status) {
      case 'rider_delivery_assigned':
        return AppColors.lenderBlue;
      case 'active':
        return AppColors.statusActive;
      case 'completed':
        return AppColors.statusCompleted;
      case 'overdue':
        return AppColors.statusOverdue;
      default:
        return AppColors.textTertiary;
    }
  }
}

class _ActionCell extends StatelessWidget {
  final LoanModel loan;
  final VoidCallback onTap;
  const _ActionCell({required this.loan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final needsRider = _needsRider(loan);
    return Tooltip(
      message: needsRider ? 'View — Rider needs assignment' : 'View details',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.deepNavy.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.deepNavy.withValues(alpha: 0.14)),
              ),
              child: const Icon(Icons.chevron_right, size: 20, color: AppColors.deepNavy),
            ),
            if (needsRider)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.warning.withValues(alpha: 0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _needsRider(LoanModel l) {
    final status = l.status.toLowerCase();
    if (['pending', 'under_review', 'ci_required'].contains(status) && (l.ciStatus == null || l.ciStatus!.isEmpty)) return true;
    if (status == 'approved' && !l.riderDeliveryAssigned) return true;
    return false;
  }
}