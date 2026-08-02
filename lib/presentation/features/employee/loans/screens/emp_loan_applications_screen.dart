// lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/emp_loan_provider.dart';

class EmpLoanApplicationsScreen extends ConsumerStatefulWidget {
  const EmpLoanApplicationsScreen({super.key});

  @override
  ConsumerState<EmpLoanApplicationsScreen> createState() =>
      _EmpLoanApplicationsScreenState();
}

class _EmpLoanApplicationsScreenState
    extends ConsumerState<EmpLoanApplicationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();

  final List<_TabDef> _tabs = [
    const _TabDef('All', null),
    const _TabDef('Pending', 'pending'),
    const _TabDef('Under Review', 'under_review'),
    const _TabDef('CI Required', 'ci_required'),
    const _TabDef('CI Assigned', 'ci_assigned'),
    const _TabDef('CI Completed', 'ci_completed'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        ref.read(empLoanProvider.notifier).setStatus(
              _tabs[_tabController.index].statusKey,
            );
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empLoanProvider);

    return WebScaffold(
      title: 'Loan Applications',
      body: Column(
        children: [
          _buildSearchBar(),
          _buildTabBar(),
          Expanded(
            child: state.isLoading
                ? _buildShimmer()
                : state.loans.isEmpty
                    ? _buildEmpty()
                    : _buildTable(state.loans),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search by loan number or lender name...',
          prefixIcon: const Icon(Icons.search, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: (v) => ref.read(empLoanProvider.notifier).setSearch(v),
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
        indicatorWeight: 3,
        tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
      ),
    );
  }

  Widget _buildTable(List<LoanModel> loans) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Column(
          children: [
            _buildTableHeader(),
            const Divider(height: 1),
            ...loans.asMap().entries.map(
                  (e) => _buildTableRow(e.value, e.key.isEven),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    const style = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 13,
      color: AppColors.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surfaceVariant,
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('Loan #', style: style)),
          Expanded(flex: 3, child: Text('Lender', style: style)),
          Expanded(flex: 2, child: Text('Amount', style: style)),
          Expanded(flex: 2, child: Text('Frequency', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
          Expanded(flex: 2, child: Text('Applied', style: style)),
          Expanded(flex: 2, child: Text('Actions', style: style)),
        ],
      ),
    );
  }

  Widget _buildTableRow(LoanModel loan, bool isEven) {
    return InkWell(
      onTap: () => context.go(
        RouteConstants.empLoanDetails.replaceFirst(':id', loan.id),
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
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.deepNavy,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                loan.lenderName ?? '—',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '₱${loan.principalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                loan.frequency.toUpperCase(),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              flex: 2,
              child: _LoanStatusBadge(status: loan.status),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${loan.createdAt.year}-${loan.createdAt.month.toString().padLeft(2, '0')}-${loan.createdAt.day.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () => context.go(
                  RouteConstants.empLoanDetails.replaceFirst(':id', loan.id),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepNavy,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: const TextStyle(fontSize: 12),
                  minimumSize: Size.zero,
                ),
                child: const Text('Review'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined,
                size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text(
              'No loan applications found',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );

  Widget _buildShimmer() => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => const ShimmerLoader(height: 56),
      );
}

class _TabDef {
  final String label;
  final String? statusKey;
  const _TabDef(this.label, this.statusKey);
}

class _LoanStatusBadge extends StatelessWidget {
  final String status;
  const _LoanStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    Color bg;
    String label;
    switch (status) {
      case 'pending':
        color = AppColors.warning;
        bg = AppColors.warningLight;
        label = 'Pending';
        break;
      case 'under_review':
        color = AppColors.info;
        bg = AppColors.infoLight;
        label = 'Under Review';
        break;
      case 'ci_required':
        color = AppColors.lenderPurple;
        bg = AppColors.lenderPurple.withValues(alpha: 0.1);
        label = 'CI Required';
        break;
      case 'ci_assigned':
        color = AppColors.riderGreen;
        bg = AppColors.riderGreen.withValues(alpha: 0.1);
        label = 'CI Assigned';
        break;
      case 'ci_completed':
        color = AppColors.deepNavy;
        bg = AppColors.deepNavy.withValues(alpha: 0.1);
        label = 'CI Completed';
        break;
      case 'approved':
        color = AppColors.success;
        bg = AppColors.successLight;
        label = 'Approved';
        break;
      case 'rejected':
        color = AppColors.error;
        bg = AppColors.errorLight;
        label = 'Rejected';
        break;
      case 'active':
        color = AppColors.riderGreen;
        bg = AppColors.successLight;
        label = 'Active';
        break;
      case 'completed':
        color = AppColors.info;
        bg = AppColors.infoLight;
        label = 'Completed';
        break;
      case 'overdue':
        color = AppColors.error;
        bg = AppColors.errorLight;
        label = 'Overdue';
        break;
      default:
        color = AppColors.textSecondary;
        bg = AppColors.surfaceVariant;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
