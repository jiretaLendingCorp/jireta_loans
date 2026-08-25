// lib/presentation/features/head_manager/riders/screens/hm_rider_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/edit_user_modal.dart';
import '../providers/hm_rider_provider.dart';
import '../widgets/create_rider_modal.dart';

class HmRiderListScreen extends ConsumerStatefulWidget {
  const HmRiderListScreen({super.key});

  @override
  ConsumerState<HmRiderListScreen> createState() => _HmRiderListScreenState();
}

class _HmRiderListScreenState extends ConsumerState<HmRiderListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmRiderProvider);

    return WebScaffold(
      title: 'Riders',
      actions: [
        ElevatedButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const CreateRiderModal(),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Rider'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.riderGreen,
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
                ? _shimmer()
                : state.riders.isEmpty
                    ? _empty()
                    : _table(state.riders),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(HmRiderState state) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search riders...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) =>
                    ref.read(hmRiderProvider.notifier).setSearch(v),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: state.statusFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Status')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                DropdownMenuItem(value: 'archived', child: Text('Archived')),
              ],
              onChanged: (v) =>
                  ref.read(hmRiderProvider.notifier).setStatus(v!),
            ),
          ],
        ),
      );

  Widget _table(List<UserModel> riders) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Column(
            children: [
              _header(),
              const Divider(height: 1),
              ...riders.asMap().entries.map((e) => _row(e.value, e.key.isEven)),
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
                'Vehicle',
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
                'Plate',
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
              child: Text(
                '${user.firstName} ${user.lastName}',
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
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
                user.vehicleType ?? '—',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.plateNumber ?? '—',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      isActive ? AppColors.successLight : AppColors.errorLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? 'Active' : _statusLabel(user.accountStatus),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.success : AppColors.error,
                  ),
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
                    () => context.go(
                      RouteConstants.hmRiderDetails.replaceFirst(
                        ':id',
                        user.id,
                      ),
                    ),
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
        initialRole: 'rider',
        initialStatus: user.accountStatus,
      ),
    );
    if (updated == true) {
      ref.read(hmRiderProvider.notifier).load();
    }
  }

  void _confirmArchive(UserModel user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Rider?'),
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
                await ref.read(hmRiderProvider.notifier).archive(user.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Rider archived successfully')),
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
            Icon(Icons.delivery_dining,
                size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text(
              'No riders found',
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
