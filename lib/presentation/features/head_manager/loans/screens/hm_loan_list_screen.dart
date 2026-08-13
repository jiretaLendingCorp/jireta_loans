// lib/presentation/features/head_manager/loans/screens/hm_loan_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/hm_loan_provider.dart';

final hmActiveLoanProvider =
    AutoDisposeStateNotifierProvider<HmLoanNotifier, HmLoanState>((ref) {
  return HmLoanNotifier(sl<LoanRemoteDataSource>(), initialFilter: 'active');
});

class HmLoanListScreen extends ConsumerStatefulWidget {
  const HmLoanListScreen({super.key});

  @override
  ConsumerState<HmLoanListScreen> createState() => _HmLoanListScreenState();
}

class _HmLoanListScreenState extends ConsumerState<HmLoanListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
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
        .read(hmActiveLoanProvider.notifier)
        .setTab(_tabs[_tabController.index].$1);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmActiveLoanProvider);
    return WebScaffold(
      title: 'Loans',
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

  Widget _buildFilters() => Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
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
          onChanged: (v) =>
              ref.read(hmActiveLoanProvider.notifier).setSearch(v),
        ),
      );

  Widget _buildTable(List<LoanModel> loans) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
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
            _buildHeader(),
            const Divider(height: 1),
            ...loans
                .asMap()
                .entries
                .map((e) => _buildRow(e.value, e.key.isEven, fmt)),
          ],
        ),
      ),
    );
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
          Expanded(flex: 2, child: Text('LOAN #', style: s)),
          Expanded(flex: 3, child: Text('LENDER', style: s)),
          Expanded(flex: 2, child: Text('PRINCIPAL', style: s)),
          Expanded(flex: 2, child: Text('OUTSTANDING', style: s)),
          Expanded(flex: 2, child: Text('DUE DATE', style: s)),
          Expanded(flex: 2, child: Text('STATUS', style: s)),
          Expanded(flex: 1, child: Text('', style: s)),
        ],
      ),
    );
  }

  Widget _buildRow(LoanModel loan, bool isEven, NumberFormat fmt) {
    final color = _statusColor(loan.status);
    return InkWell(
      onTap: () =>
          context.go(RouteConstants.hmLoanDetails.replaceFirst(':id', loan.id)),
      child: Container(
        color: isEven
            ? Colors.white
            : AppColors.surfaceVariant.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
                flex: 2,
                child: Text(loan.loanNumber,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
            Expanded(
                flex: 3,
                child: Text(loan.lenderName ?? '-',
                    style: const TextStyle(fontSize: 13))),
            Expanded(
                flex: 2,
                child: Text('₱${fmt.format(loan.principalAmount)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500))),
            Expanded(
              flex: 2,
              child: Text(
                '₱${fmt.format(loan.outstandingBalance)}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: loan.status == 'overdue'
                        ? AppColors.error
                        : AppColors.textPrimary),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                loan.dueDate != null
                    ? DateFormat('MMM dd, yyyy').format(loan.dueDate!)
                    : '-',
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
                    borderRadius: BorderRadius.circular(4)),
                child: Text(
                  loan.status
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
            ),
            Expanded(
                flex: 1,
                child: IconButton(
                    onPressed: () => context.go(RouteConstants.hmLoanDetails
                        .replaceFirst(':id', loan.id)),
                    icon: const Icon(Icons.chevron_right,
                        size: 20, color: AppColors.textSecondary))),
          ],
        ),
      ),
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

  Widget _buildPagination(HmLoanState state) => Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: state.currentPage > 1
                  ? () => ref
                      .read(hmActiveLoanProvider.notifier)
                      .fetchLoans(page: state.currentPage - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Page ${state.currentPage} of ${state.totalPages}',
                style: const TextStyle(fontSize: 14)),
            IconButton(
              onPressed: state.currentPage < state.totalPages
                  ? () => ref
                      .read(hmActiveLoanProvider.notifier)
                      .fetchLoans(page: state.currentPage + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );

  Color _statusColor(String status) {
    switch (status) {
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
