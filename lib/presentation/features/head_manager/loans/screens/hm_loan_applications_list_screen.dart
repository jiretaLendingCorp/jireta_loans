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
import '../../ci/widgets/ci_assign_modal.dart';
import '../../disbursements/widgets/rider_disburse_assign_modal.dart';
import '../providers/hm_loan_provider.dart';
import '../widgets/approve_reject_modal.dart';

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
          Expanded(flex: 4, child: Text('Action', style: s)),
        ],
      ),
    );
  }

  Widget _buildRow(LoanModel loan, bool isEven) {
    final color = _statusColor(loan.displayStatus);
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    return InkWell(
      onTap: () => context.go(
        RouteConstants.hmLoanApplicationDetails.replaceFirst(':id', loan.id),
      ),
      child: Container(
        color: isEven
            ? Colors.white
            : AppColors.surfaceVariant.withValues(alpha: 0.3),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatStatus(loan.displayStatus),
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w500),
                    ),
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
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.riderGreen,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: _buildActions(loan),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(LoanModel loan) {
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

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (canApprove)
          _InlineActionButton(
            label: 'Approve',
            icon: Icons.check_circle_outline,
            color: AppColors.success,
            onPressed: () => _showApprove(loan),
          ),
        if (canAssignDeliveryRider)
          _InlineActionButton(
            label: 'Assign Delivery Rider',
            icon: Icons.delivery_dining,
            color: AppColors.gold,
            onPressed: () => _showAssignDisbursementRider(loan),
          ),
        if (canAssignRider)
          _InlineActionButton(
            label: 'Assign Rider',
            icon: Icons.delivery_dining,
            color: AppColors.info,
            onPressed: () => _showAssignRider(loan),
          ),
        if (canReject)
          _InlineActionButton(
            label: 'Reject',
            icon: Icons.cancel_outlined,
            color: AppColors.error,
            onPressed: () => _showReject(loan),
          ),
        _InlineActionButton(
          label: 'View',
          icon: Icons.visibility_outlined,
          color: AppColors.textSecondary,
          onPressed: () => context.go(
            RouteConstants.hmLoanApplicationDetails
                .replaceFirst(':id', loan.id),
          ),
        ),
      ],
    );
  }

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
          ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery rider assigned'),
          backgroundColor: AppColors.success,
        ),
      );
      ref.read(hmLoanProvider.notifier).fetchLoans();
    }
  }

  Future<void> _showAssignRider(LoanModel loan) async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => CiAssignModal(loanId: loan.id),
    );
    if (assigned == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider assigned for credit investigation'),
          backgroundColor: AppColors.success,
        ),
      );
      ref.read(hmLoanProvider.notifier).fetchLoans();
    }
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ok ? 'Loan rejected' : 'Reject failed'),
              backgroundColor: ok ? AppColors.error : AppColors.textSecondary,
            ),
          );
        },
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
        return AppColors.lenderBlue;
      case 'rider_delivery_assigned':
        return AppColors.lenderBlue;
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

class _InlineActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _InlineActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15, color: color),
      label: Text(label,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        backgroundColor: color.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
