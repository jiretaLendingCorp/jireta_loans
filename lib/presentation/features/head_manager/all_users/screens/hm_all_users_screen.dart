// lib/presentation/features/head_manager/all_users/screens/hm_all_users_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';
import '../../../../shared/widgets/details/user_details_modal.dart';
import '../../../../shared/widgets/edit_user_modal.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../providers/hm_all_users_provider.dart';

class HmAllUsersScreen extends ConsumerStatefulWidget {
  const HmAllUsersScreen({super.key});

  @override
  ConsumerState<HmAllUsersScreen> createState() => _HmAllUsersScreenState();
}

class _HmAllUsersScreenState extends ConsumerState<HmAllUsersScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    ref.read(hmAllUsersProvider.notifier).setDateRange(
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
    final state = ref.watch(hmAllUsersProvider);
    return WebScaffold(
      title: 'All People',
      body: Column(
        children: [
          _filters(state),
          Expanded(
            // Shimmer only replaces the body on the very first load. Search /
            // filter / create keep the current table visible until the new
            // result arrives so the screen never flashes "loading everything".
            child: state.isLoading && state.users.isEmpty
                ? _shimmer()
                : state.users.isEmpty
                    ? _empty()
                    : _table(state.users),
          ),
        ],
      ),
    );
  }

  Widget _filters(HmAllUsersState state) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: ResponsiveSearchToolbar(
          searchField: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by name, email or phone...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) =>
                ref.read(hmAllUsersProvider.notifier).setSearch(v),
          ),
          trailing: [
            SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
            SearchResultsChip(count: state.users.length),
            DropdownButton<String>(
              value: state.roleFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Roles')),
                DropdownMenuItem(
                    value: 'head_manager', child: Text('Head Manager')),
                DropdownMenuItem(value: 'employee', child: Text('Employee')),
                DropdownMenuItem(value: 'rider', child: Text('Rider')),
                DropdownMenuItem(value: 'lender', child: Text('Lender')),
              ],
              onChanged: (v) =>
                  ref.read(hmAllUsersProvider.notifier).setRole(v!),
            ),
            DropdownButton<String>(
              value: state.statusFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Status')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              onChanged: (v) =>
                  ref.read(hmAllUsersProvider.notifier).setStatus(v!),
            ),
          ],
        ),
      );

  Widget _table(List<UserModel> users) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ResponsiveListCard(
          minTableWidth: 780,
          variant: ResponsiveListVariant.card,
          columns: const [
            ResponsiveCol('Name', flex: 3),
            ResponsiveCol('Role', flex: 2),
            ResponsiveCol('Phone', flex: 2),
            ResponsiveCol('Email', flex: 2),
            ResponsiveCol('Status', flex: 1),
          ],
          actionsCol: const ResponsiveActionsCol(label: 'Actions', flex: 2),
          rows: users.map((e) => _row(e)).toList(),
        ),
      );

  ResponsiveRow _row(UserModel user) {
    final isActive = user.accountStatus == 'active';
    final isArchived = user.accountStatus == 'archived';
    return ResponsiveRow(
      cells: [
        Row(
          children: [
            ProfileAvatar(
              photoUrl: user.profilePhotoUrl,
              name: '${user.firstName} ${user.lastName}',
              color: _roleColor(user.role),
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
        Text(
          _roleLabel(user.role),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _roleColor(user.role),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          user.phoneNumber ?? '—',
          style:
              const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        Text(
          user.email ?? '—',
          style:
              const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
          _btn(
            Icons.visibility_outlined,
            'View',
            AppColors.textSecondary,
            () => _goToDetails(user),
          ),
          _btn(
            Icons.edit_outlined,
            'Edit',
            AppColors.primary,
            () => _openEdit(user),
          ),
          // Reset Password is only for Head Manager and Employee accounts.
          if (!isArchived &&
              (user.role == 'head_manager' || user.role == 'employee'))
            _btn(
              Icons.password_rounded,
              'Reset Password',
              AppColors.deepNavy,
              () => _showResetPassword(user),
            ),
          if (!isArchived && user.role != 'head_manager')
            _btn(
              Icons.archive_outlined,
              'Archive',
              AppColors.error,
              () => _confirmArchive(user),
            ),
        ],
      ),
    );
  }

  void _goToDetails(UserModel user) {
    // All PEOPLE roles now use modal with zero radius and fit to details
    showUserDetailsModal(context, user);
  }

  void _confirmArchive(UserModel user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Archive ${_roleLabel(user.role)}?'),
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
                await ref.read(hmAllUsersProvider.notifier).archive(user.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            '${_roleLabel(user.role)} archived successfully')),
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

  void _showResetPassword(UserModel user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('Reset Password'),
        content: Text(
          'Reset the password of ${user.firstName} ${user.lastName}? '
          'It will be set to 12345678 and they will be required to change it on next login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepNavy,
              foregroundColor: Colors.white,
              shape:
                  const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref
                    .read(hmAllUsersProvider.notifier)
                    .resetPassword(user.id);
                if (mounted) {
                  context.showToast('Password reset to 12345678');
                }
              } catch (e) {
                if (mounted) {
                  context.showErrorToast('Failed to reset: $e');
                }
              }
            },
            child: const Text('Reset'),
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
        initialRole: user.role,
        initialStatus: user.accountStatus,
        showRole: false,
      ),
    );
    if (updated == true) {
      ref.read(hmAllUsersProvider.notifier).load();
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'employee':
        return AppColors.employeeOrange;
      case 'rider':
        return AppColors.riderGreen;
      case 'lender':
        return AppColors.lenderBlue;
      case 'head_manager':
        return AppColors.gold;
      default:
        return AppColors.textSecondary;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'head_manager':
        return 'Head Manager';
      case 'employee':
        return 'Employee';
      case 'rider':
        return 'Rider';
      case 'lender':
        return 'Lender';
      default:
        return role;
    }
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

  Widget _btn(IconData icon, String tip, Color color, VoidCallback onTap) =>
      Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      );

  Widget _empty() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_outlined, size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text('No people found',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
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
