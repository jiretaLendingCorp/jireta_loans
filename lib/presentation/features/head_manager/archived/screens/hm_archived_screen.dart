// lib/presentation/features/head_manager/archived/screens/hm_archived_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/hm_archived_provider.dart';

class HmArchivedScreen extends ConsumerStatefulWidget {
  const HmArchivedScreen({super.key});

  @override
  ConsumerState<HmArchivedScreen> createState() => _HmArchivedScreenState();
}

class _HmArchivedScreenState extends ConsumerState<HmArchivedScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmArchivedProvider);
    return WebScaffold(
      title: 'Archived',
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

  Widget _filters(HmArchivedState state) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search archived by name, email or phone...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) =>
                    ref.read(hmArchivedProvider.notifier).setSearch(v),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: state.roleFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Roles')),
                DropdownMenuItem(value: 'employee', child: Text('Employee')),
                DropdownMenuItem(value: 'rider', child: Text('Rider')),
                DropdownMenuItem(value: 'lender', child: Text('Lender')),
              ],
              onChanged: (v) =>
                  ref.read(hmArchivedProvider.notifier).setRole(v!),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.archive_outlined,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: 6),
                  Text(
                    '${state.users.length} archived',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
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
            Expanded(flex: 2, child: Text('Role', style: _hdrStyle)),
            Expanded(flex: 2, child: Text('Phone', style: _hdrStyle)),
            Expanded(flex: 2, child: Text('Email', style: _hdrStyle)),
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
            child: Text(
              '${user.firstName} ${user.lastName}',
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _roleLabel(user.role),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _roleColor(user.role),
              ),
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
            flex: 2,
            child: Text(
              user.email ?? '—',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Archived',
                style: TextStyle(
                    color: AppColors.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
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
                  () => _goToDetails(user),
                ),
                _btn(
                  Icons.unarchive_outlined,
                  'Restore',
                  AppColors.success,
                  () => _confirmRestore(user),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _goToDetails(UserModel user) {
    switch (user.role) {
      case 'employee':
        context.go(RouteConstants.hmEmployeeDetails.replaceFirst(':id', user.id));
        break;
      case 'rider':
        context.go(RouteConstants.hmRiderDetails.replaceFirst(':id', user.id));
        break;
      case 'lender':
        context.go(RouteConstants.hmLenderDetails.replaceFirst(':id', user.id));
        break;
      default:
        break;
    }
  }

  void _confirmRestore(UserModel user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore User?'),
        content: Text(
          'Restore ${user.firstName} ${user.lastName} to Active status? They will reappear in People lists.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(hmArchivedProvider.notifier).restore(user.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            '${_roleLabel(user.role)} restored successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to restore: $e')),
                  );
                }
              }
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'employee':
        return AppColors.deepNavy;
      case 'rider':
        return AppColors.riderGreen;
      case 'lender':
        return AppColors.lenderBlue;
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
            Icon(Icons.archive_outlined,
                size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text('No archived users',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            SizedBox(height: 8),
            Text('Archived people will appear here',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
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
