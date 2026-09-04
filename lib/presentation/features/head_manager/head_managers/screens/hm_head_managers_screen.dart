// lib/presentation/features/head_manager/head_managers/screens/hm_head_managers_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';
import '../../../../shared/widgets/details/user_details_modal.dart';
import '../../../../shared/widgets/edit_user_modal.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../providers/hm_head_managers_provider.dart';
import '../widgets/create_head_manager_modal.dart';

class HmHeadManagersScreen extends ConsumerStatefulWidget {
  const HmHeadManagersScreen({super.key});

  @override
  ConsumerState<HmHeadManagersScreen> createState() =>
      _HmHeadManagersScreenState();
}

class _HmHeadManagersScreenState extends ConsumerState<HmHeadManagersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmHeadManagersProvider);
    return WebScaffold(
      title: 'Head Managers',
      actions: [
        ElevatedButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const CreateHeadManagerModal(),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Create Head Manager'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black87,
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
                : state.users.isEmpty
                    ? _empty()
                    : _table(state.users),
          ),
        ],
      ),
    );
  }

  Widget _filters(HmHeadManagersState state) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search head managers...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => ref
                    .read(hmHeadManagersProvider.notifier)
                    .setSearch(v),
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
                  ref.read(hmHeadManagersProvider.notifier).setStatus(v!),
            ),
          ],
        ),
      );

  Widget _table(List<UserModel> users) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Column(
            children: [
              _header(),
              const Divider(height: 1),
              ...users.asMap().entries.map((e) => _row(e.value, e.key.isEven)),
            ],
          ),
        ),
      );

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: AppColors.surfaceVariant,
        child: const Row(
          children: [
            Expanded(flex: 3, child: Text('Name', style: _hdrStyle)),
            Expanded(flex: 3, child: Text('Email', style: _hdrStyle)),
            Expanded(flex: 2, child: Text('Phone', style: _hdrStyle)),
            Expanded(flex: 1, child: Text('Status', style: _hdrStyle)),
            Expanded(flex: 2, child: Text('Actions', style: _hdrStyle)),
          ],
        ),
      );

  static const _hdrStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: AppColors.textSecondary,
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
                ProfileAvatar(
                  photoUrl: user.profilePhotoUrl,
                  name: '${user.firstName} ${user.lastName}',
                  color: AppColors.gold,
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
            flex: 3,
            child: Text(
              user.email ?? '—',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user.phoneNumber ?? '—',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
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
                _btn(
                  Icons.password_rounded,
                  'Reset Password',
                  AppColors.deepNavy,
                  () => _showResetPassword(user),
                ),
              ],
            ),
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
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref
                    .read(hmHeadManagersProvider.notifier)
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
      ref.read(hmHeadManagersProvider.notifier).load();
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
            Icon(Icons.admin_panel_settings_outlined,
                size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text('No head managers found',
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
