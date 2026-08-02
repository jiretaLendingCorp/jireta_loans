// lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/hm_loan_provider.dart';

class HmLoanApplicationsListScreen extends ConsumerStatefulWidget {
  const HmLoanApplicationsListScreen({super.key});

  @override
  ConsumerState<HmLoanApplicationsListScreen> createState() =>
      _HmLoanApplicationsListScreenState();
}

class _HmLoanApplicationsListScreenState
    extends ConsumerState<HmLoanApplicationsListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  final _tabs = [
    ('all', 'All'),
    ('pending', 'Pending'),
    ('under_review', 'Under Review'),
    ('ci_required', 'CI Required'),
    ('ci_assigned', 'CI Assigned'),
    ('ci_completed', 'CI Completed'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    ref.read(hmLoanProvider.notifier).setTab(_tabs[_tabController.index].$1);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmLoanProvider);
    return WebScaffold(
      title: 'Loan Applications',
      body: Column(
        children: [
          _buildTabBar(),
          _buildFilters(),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.loans.isEmpty
                    ? _buildEmpty()
                    : _buildTable(state.loans),
          ),
          if (state.totalPages > 1) _buildPagination(state),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
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
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
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
              onChanged: (v) => ref.read(hmLoanProvider.notifier).setSearch(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<LoanModel> loans) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Column(
          children: [
            _buildTableHeader(),
            const Divider(height: 1),
            ...loans
                .asMap()
                .entries
                .map((e) => _buildRow(e.value, e.key.isEven)),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    const s = TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surfaceVariant,
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('Loan #', style: s)),
          Expanded(flex: 3, child: Text('Lender', style: s)),
          Expanded(flex: 2, child: Text('Amount', style: s)),
          Expanded(flex: 2, child: Text('Frequency', style: s)),
          Expanded(flex: 2, child: Text('Date Applied', style: s)),
          Expanded(flex: 2, child: Text('Status', style: s)),
          Expanded(flex: 1, child: Text('Action', style: s)),
        ],
      ),
    );
  }

  Widget _buildRow(LoanModel loan, bool isEven) {
    final color = _statusColor(loan.status);
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    return InkWell(
      onTap: () => context.go(
        RouteConstants.hmLoanApplicationDetails.replaceFirst(':id', loan.id),
      ),
      child: Container(
        color:
            isEven ? Colors.white : AppColors.surfaceVariant.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                loan.loanNumber,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                '${loan.lenderFirstName} ${loan.lenderLastName}'.trim(),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '₱${fmt.format(loan.principalAmount)}',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _capitalizeFirst(loan.paymentFrequency),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                DateFormat('MMM dd, yyyy').format(loan.createdAt),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatStatus(loan.status),
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: IconButton(
                onPressed: () => context.go(
                  RouteConstants.hmLoanApplicationDetails
                      .replaceFirst(':id', loan.id),
                ),
                icon: const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.textSecondary),
                tooltip: 'View Details',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined,
              size: 64, color: AppColors.textTertiary),
          SizedBox(height: 16),
          Text('No loan applications found',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildPagination(HmLoanState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: state.currentPage > 1
                ? () => ref
                    .read(hmLoanProvider.notifier)
                    .fetchLoans(page: state.currentPage - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Page ${state.currentPage} of ${state.totalPages}',
              style: const TextStyle(fontSize: 14)),
          IconButton(
            onPressed: state.currentPage < state.totalPages
                ? () => ref
                    .read(hmLoanProvider.notifier)
                    .fetchLoans(page: state.currentPage + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.statusPending;
      case 'under_review':
        return AppColors.info;
      case 'ci_required':
        return AppColors.warning;
      case 'ci_assigned':
        return AppColors.gold;
      case 'ci_completed':
        return AppColors.lenderPurple;
      case 'approved':
        return AppColors.statusActive;
      case 'active':
        return AppColors.statusActive;
      case 'rejected':
        return AppColors.statusRejected;
      case 'cancelled':
        return AppColors.textSecondary;
      case 'completed':
        return AppColors.statusCompleted;
      case 'overdue':
        return AppColors.statusOverdue;
      default:
        return AppColors.textTertiary;
    }
  }

  String _formatStatus(String status) =>
      status.replaceAll('_', ' ').split(' ').map(_capitalizeFirst).join(' ');

  String _capitalizeFirst(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
