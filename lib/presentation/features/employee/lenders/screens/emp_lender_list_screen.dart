// lib/presentation/features/employee/lenders/screens/emp_lender_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/details/user_details_modal.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../providers/emp_lender_provider.dart';
import '../widgets/emp_register_lender_modal.dart';

class EmpLenderListScreen extends ConsumerStatefulWidget {
  const EmpLenderListScreen({super.key});

  @override
  ConsumerState<EmpLenderListScreen> createState() =>
      _EmpLenderListScreenState();
}

class _EmpLenderListScreenState extends ConsumerState<EmpLenderListScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    ref.read(empLenderProvider.notifier).setDateRange(
          r == null ? null : SearchDateFilter.fromParam(r.start),
          r == null ? null : SearchDateFilter.toParam(r.end),
        );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empLenderProvider);

    return WebScaffold(
      title: 'Lenders',
      actions: [
        ElevatedButton.icon(
          onPressed: () => _showRegisterModal(context),
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Create Lender'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.lenderBlue,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
      ],
      body: Column(
        children: [
          _buildFilters(state),
          Expanded(
            child: state.isLoading
                ? _buildShimmer()
                : state.lenders.isEmpty
                    ? _buildEmpty()
                    : _buildTable(state.lenders),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(EmpLenderState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: ResponsiveSearchToolbar(
        searchField: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search lenders by name or phone...',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (v) =>
              ref.read(empLenderProvider.notifier).setSearch(v),
        ),
        trailing: [
          SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
          SearchResultsChip(count: state.lenders.length),
          DropdownButton<String>(
            value: state.statusFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All Status')),
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
            ],
            onChanged: (v) =>
                ref.read(empLenderProvider.notifier).setStatus(v!),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<UserModel> lenders) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ResponsiveListCard(
        minTableWidth: 820,
        variant: ResponsiveListVariant.card,
        columns: const [
          ResponsiveCol('Name', flex: 3),
          ResponsiveCol('Phone', flex: 2),
          ResponsiveCol('Account Upgrade Status', flex: 2),
          ResponsiveCol('Status', flex: 1),
        ],
        actionsCol: const ResponsiveActionsCol(label: 'Actions', flex: 2),
        rows: lenders.map((e) => _buildTableRow(e)).toList(),
      ),
    );
  }

  ResponsiveRow _buildTableRow(UserModel user) {
    final isActive = user.accountStatus == 'active';
    return ResponsiveRow(
      onTap: () => showUserDetailsModal(context, user),
      cells: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: AppColors.lenderBlue, shape: BoxShape.circle),
              child: const Icon(Icons.person_rounded, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${user.firstName} ${user.lastName}'.trim().isEmpty ? 'N/A' : '${user.firstName} ${user.lastName}',
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(
          user.phoneNumber ?? 'N/A',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          user.accountUpgradeStatus == null ||
                  user.accountUpgradeStatus!.isEmpty
              ? 'N/A'
              : _accountUpgradeLabel(user.accountUpgradeStatus!),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: user.accountUpgradeStatus == null ||
                    user.accountUpgradeStatus!.isEmpty
                ? AppColors.textSecondary
                : _accountUpgradeColor(user.accountUpgradeStatus!),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          isActive ? 'Active' : _statusLabel(user.accountStatus),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isActive ? AppColors.success : AppColors.error,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionBtn(
            icon: Icons.visibility_outlined,
            tooltip: 'View Details',
            onTap: () => showUserDetailsModal(context, user),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'inactive':
        return 'Inactive';
      case 'archived':
        return 'Archived';
      default:
        return 'Inactive';
    }
  }

  String _accountUpgradeLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'under_review':
        return 'Under Review';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'verified':
        return 'Verified';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Color _accountUpgradeColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'verified':
      case 'whitelisted':
        return AppColors.success;
      case 'pending':
      case 'under_review':
      case 'requested':
        return AppColors.warning;
      case 'rejected':
      case 'blacklisted':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildEmpty() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text(
              'No lenders found',
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

  void _showRegisterModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const EmpRegisterLenderModal(),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isView = tooltip == 'View Details';
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isView ? Colors.white : Colors.transparent,
            border: Border.all(
                color: isView ? AppColors.border : Colors.transparent),
          ),
          child: Icon(icon,
              size: 16,
              color: isView ? AppColors.deepNavy : AppColors.textSecondary),
        ),
      ),
    );
  }
}
