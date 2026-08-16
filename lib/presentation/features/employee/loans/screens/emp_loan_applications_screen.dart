// lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../ci/widgets/emp_ci_assign_modal.dart';
import '../../../head_manager/loans/widgets/approve_reject_modal.dart';
import '../../../head_manager/disbursements/widgets/rider_disburse_assign_modal.dart';
import '../providers/emp_loan_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

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
          Expanded(flex: 4, child: Text('Actions', style: style)),
        ],
      ),
    );
  }

  Widget _buildTableRow(LoanModel loan, bool isEven) {
    return InkWell(
      key: ValueKey(loan.id),
      onTap: () => context.go(
        RouteConstants.empLoanDetails.replaceFirst(':id', loan.id),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LoanStatusBadge(status: loan.displayStatus),
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
          _EmpLoanActionButton(
            label: 'Approve',
            icon: Icons.check_circle_outline,
            color: AppColors.success,
            onPressed: () => _showApprove(loan),
          ),
        if (canAssignDeliveryRider)
          _EmpLoanActionButton(
            label: 'Assign Delivery Rider',
            icon: Icons.delivery_dining,
            color: AppColors.gold,
            onPressed: () => _showAssignDeliveryRider(loan),
          ),
        if (canAssignRider)
          _EmpLoanActionButton(
            label: 'Assign Rider',
            icon: Icons.delivery_dining,
            color: AppColors.info,
            onPressed: () => _showAssignRider(loan),
          ),
        if (canReject)
          _EmpLoanActionButton(
            label: 'Reject',
            icon: Icons.cancel_outlined,
            color: AppColors.error,
            onPressed: () => _showReject(loan),
          ),
        _EmpLoanActionButton(
          label: 'Review',
          icon: Icons.visibility_outlined,
          color: AppColors.textSecondary,
          onPressed: () => context.go(
            RouteConstants.empLoanDetails.replaceFirst(':id', loan.id),
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

class _EmpLoanActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _EmpLoanActionButton({
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
        color = AppColors.lenderBlue;
        bg = AppColors.lenderBlue.withValues(alpha: 0.1);
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
      case 'rider_delivery_assigned':
        color = AppColors.lenderBlue;
        bg = AppColors.lenderBlue.withValues(alpha: 0.1);
        label = 'Rider Delivery Assigned';
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
