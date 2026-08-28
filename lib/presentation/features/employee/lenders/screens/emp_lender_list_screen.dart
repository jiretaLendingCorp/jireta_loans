// lib/presentation/features/employee/lenders/screens/emp_lender_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/profile_avatar.dart';
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
          label: const Text('Register Lender'),
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
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
          ),
          const SizedBox(width: 12),
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
      child: Card(
        child: Column(
          children: [
            _buildTableHeader(),
            const Divider(height: 1),
            ...lenders.asMap().entries.map(
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
          Expanded(flex: 3, child: Text('Name', style: style)),
          Expanded(flex: 2, child: Text('Phone', style: style)),
          Expanded(flex: 2, child: Text('GCash Number', style: style)),
          Expanded(
              flex: 2, child: Text('Account Upgrade Status', style: style)),
          Expanded(flex: 1, child: Text('Status', style: style)),
          Expanded(flex: 2, child: Text('Actions', style: style)),
        ],
      ),
    );
  }

  Widget _buildTableRow(UserModel user, bool isEven) {
    final isActive = user.accountStatus == 'active';
    return InkWell(
      key: ValueKey(user.id),
      onTap: () => context.go(
        RouteConstants.empLenderDetails.replaceFirst(':id', user.id),
      ),
      child: Container(
        color: isEven
            ? Colors.white
            : AppColors.surfaceVariant.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  ProfileAvatar(
                    photoUrl: user.profilePhotoUrl,
                    name: user.firstName,
                    color: AppColors.lenderBlue,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      '${user.firstName} ${user.lastName}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.phoneNumber ?? '—',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.gcashNumber ?? '—',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.accountUpgradeStatus == null ||
                        user.accountUpgradeStatus!.isEmpty
                    ? '—'
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
            ),
            Expanded(
              flex: 1,
              child: Text(
                isActive ? 'Active' : _statusLabel(user.accountStatus),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isActive ? AppColors.success : AppColors.error,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  _ActionBtn(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View Details',
                    onTap: () => context.go(
                      RouteConstants.empLenderDetails.replaceFirst(
                        ':id',
                        user.id,
                      ),
                    ),
                  ),
                 ],
               ),
            ),
          ],
        ),
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
