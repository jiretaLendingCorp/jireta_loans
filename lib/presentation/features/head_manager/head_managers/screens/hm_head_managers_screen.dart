// lib/presentation/features/head_manager/head_managers/screens/hm_head_managers_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/details/user_details_modal.dart';
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
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const CreateHeadManagerModal(),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero),
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Create Head Manager'),
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
    final formKey = GlobalKey<FormState>();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape:
              const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Text('Reset Password'),
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Set a new password for ${user.firstName} ${user.lastName}. They will be required to change it on next login.',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  _dialogField(
                    passCtrl,
                    'New Password *',
                    obscure: true,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Password is required';
                      }
                      if (v.length < 6) {
                        return 'At least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    confirmCtrl,
                    'Confirm Password *',
                    obscure: true,
                    validator: (v) {
                      if (v != passCtrl.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
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
              onPressed: submitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => submitting = true);
                      try {
                        await ref
                            .read(hmHeadManagersProvider.notifier)
                            .resetPassword(user.id, passCtrl.text);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Password reset successfully. User must change it on next login.')),
                        );
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setState(() => submitting = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Failed to reset: $e')),
                        );
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogField(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        obscureText: obscure,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.border),
          ),
          isDense: true,
        ),
      );

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
