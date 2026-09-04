// lib/presentation/features/head_manager/lenders/screens/hm_lender_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/details/user_details_modal.dart';
import '../../../../shared/widgets/edit_user_modal.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/hm_lender_provider.dart';
import '../widgets/create_lender_modal.dart';

class HmLenderListScreen extends ConsumerStatefulWidget {
  const HmLenderListScreen({super.key});

  @override
  ConsumerState<HmLenderListScreen> createState() => _HmLenderListScreenState();
}

class _HmLenderListScreenState extends ConsumerState<HmLenderListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmLenderProvider);
    return WebScaffold(
      title: 'Lenders',
      actions: [
        ElevatedButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const CreateLenderModal(),
          ),
          icon: const Icon(Icons.person_add, size: 18),
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
          _filters(state),
          Expanded(
            child: state.isLoading
                ? _shimmer()
                : state.lenders.isEmpty
                    ? _empty()
                    : _table(state.lenders),
          ),
        ],
      ),
    );
  }

  Widget _filters(HmLenderState state) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search lenders...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) =>
                    ref.read(hmLenderProvider.notifier).setSearch(v),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: state.statusFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              onChanged: (v) =>
                  ref.read(hmLenderProvider.notifier).setStatus(v!),
            ),
          ],
        ),
      );

  Widget _table(List<UserModel> lenders) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Column(
            children: [
              _header(),
              const Divider(height: 1),
              ...lenders
                  .asMap()
                  .entries
                  .map((e) => _row(e.value, e.key.isEven)),
            ],
          ),
        ),
      );

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: AppColors.surfaceVariant,
        child: const Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                'Name',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Phone',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Account Upgrade Status',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                'Status',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Actions',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _row(UserModel user, bool isEven) {
    final isActive = user.accountStatus == 'active';
    return Container(
      key: ValueKey(user.id),
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
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.phoneNumber ?? 'N/A',
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
                  _btn(
                    Icons.visibility_outlined,
                    'View',
                    AppColors.textSecondary,
                    () => showUserDetailsModal(context, user),
                  ),
                  _btn(
                    Icons.edit_outlined,
                    'Edit',
                    AppColors.primary,
                    () => _openEdit(user),
                  ),
                  if (user.accountStatus != 'archived')
                    _btn(
                      Icons.archive_outlined,
                      'Archive',
                      AppColors.error,
                      () => _confirmArchive(user),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Future<void> _openEdit(UserModel user) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => EditUserModal(
        userId: user.id,
        initialRole: 'lender',
        initialStatus: user.accountStatus,
      ),
    );
    if (updated == true) {
      ref.read(hmLenderProvider.notifier).load();
    }
  }

  void _confirmArchive(UserModel user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Lender?'),
        content: Text(
          'This will archive ${user.firstName} ${user.lastName}. This action cannot be undone easily.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(hmLenderProvider.notifier).archive(user.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lender archived successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to archive: $e')),
                  );
                }
              }
            },
            child: const Text('Archive'),
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

  Widget _btn(IconData icon, String tip, Color color, VoidCallback onTap) {
    final isView = tip == 'View';
    return Tooltip(
      message: tip,
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
              size: 16, color: isView ? AppColors.deepNavy : color),
        ),
      ),
    );
  }

  Widget _empty() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text(
              'No lenders found',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );

  Widget _shimmer() => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => const ShimmerLoader(height: 56),
      );
}
