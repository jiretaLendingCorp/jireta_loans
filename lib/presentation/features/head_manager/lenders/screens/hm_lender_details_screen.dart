// lib/presentation/features/head_manager/lenders/screens/hm_lender_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../providers/hm_lender_provider.dart';

final _lenderDetailProvider = FutureProvider.family<UserModel, String>((
  ref,
  id,
) async {
  return sl<UserRemoteDataSource>().getProfile(userId: id);
});

class HmLenderDetailsScreen extends ConsumerWidget {
  final String userId;
  const HmLenderDetailsScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_lenderDetailProvider(userId));
    return WebScaffold(
      title: 'Lender Details',
      actions: [
        TextButton.icon(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
        ),
        const SizedBox(width: 8),
      ],
      body: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: ShimmerLoader(height: 300),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _profileCard(user),
              const SizedBox(height: 20),
              _infoCard(user),
              const SizedBox(height: 20),
              _actionsCard(context, ref, user),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard(UserModel user) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        ProfileAvatar(
          photoUrl: user.profilePhotoUrl,
          name: user.firstName,
          color: AppColors.lenderPurple,
          radius: 40,
        ),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${user.firstName} ${user.lastName}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Text(
              user.phoneNumber ?? '—',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: user.accountStatus == 'active'
                    ? AppColors.successLight
                    : AppColors.errorLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                user.accountStatus.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: user.accountStatus == 'active'
                      ? AppColors.success
                      : AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _infoCard(UserModel user) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lender Information',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const Divider(height: 24),
        _row('Phone', user.phoneNumber ?? '—'),
        _row('Email', user.email ?? '—'),
        _row('Status', user.accountStatus),
        _row('Member Since', user.createdAt.toString().substring(0, 10)),
      ],
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );

  Widget _actionsCard(BuildContext context, WidgetRef ref, UserModel user) {
    final isActive = user.accountStatus == 'active';
    final reasonCtrl = TextEditingController();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Actions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  await ref
                      .read(hmLenderProvider.notifier)
                      .suspendActivate(
                        user.id,
                        isActive ? 'suspend' : 'activate',
                      );
                  ref.invalidate(_lenderDetailProvider(userId));
                },
                icon: Icon(
                  isActive
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
                label: Text(isActive ? 'Suspend' : 'Activate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Blacklist Lender'),
                      content: TextField(
                        controller: reasonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                          onPressed: () async {
                            Navigator.pop(context);
                            await ref
                                .read(hmLenderProvider.notifier)
                                .addBlacklist(user.id, reasonCtrl.text);
                          },
                          child: const Text('Blacklist'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.block),
                label: const Text('Blacklist'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  await ref.read(hmLenderProvider.notifier).archive(user.id);
                  if (context.mounted) context.pop();
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
