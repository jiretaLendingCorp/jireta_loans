// lib/presentation/features/head_manager/employees/screens/hm_employee_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../providers/hm_employee_provider.dart';

final _empDetailProvider = FutureProvider.family<UserModel, String>((
  ref,
  id,
) async {
  return sl<UserRemoteDataSource>().getProfile(userId: id);
});

class HmEmployeeDetailsScreen extends ConsumerWidget {
  final String userId;
  const HmEmployeeDetailsScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_empDetailProvider(userId));

    return WebScaffold(
      title: 'Employee Details',
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
          child: Column(
            children: [
              ShimmerLoader(height: 200),
              SizedBox(height: 16),
              ShimmerLoader(height: 150),
            ],
          ),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) => _buildBody(context, ref, user),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, UserModel user) {
    final isActive = user.accountStatus == 'active';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileCard(user),
          const SizedBox(height: 20),
          _buildInfoCard(user),
          const SizedBox(height: 20),
          _buildActionsCard(context, ref, user, isActive),
        ],
      ),
    );
  }

  Widget _buildProfileCard(UserModel user) => Container(
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
          color: AppColors.deepNavy,
          radius: 40,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${user.firstName} ${user.middleName != null ? '${user.middleName} ' : ''}${user.lastName}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user.email ?? '—',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
        ),
      ],
    ),
  );

  Widget _buildInfoCard(UserModel user) => Container(
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
          'Account Information',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        _infoRow('Role', 'Employee'),
        _infoRow('Email', user.email ?? '—'),
        _infoRow('Phone', user.phoneNumber ?? '—'),
        _infoRow('Department', user.department ?? '—'),
        _infoRow('Position', user.position ?? '—'),
        _infoRow('Gender', user.gender ?? '—'),
        _infoRow('Civil Status', user.civilStatus ?? '—'),
        _infoRow('Created At', user.createdAt.toString().substring(0, 10)),
        _infoRow(
          'Last Login',
          user.lastLoginAt?.toString().substring(0, 16) ?? '—',
        ),
      ],
    ),
  );

  Widget _infoRow(String label, String value) => Padding(
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

  Widget _buildActionsCard(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
    bool isActive,
  ) => Container(
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
                    .read(hmEmployeeProvider.notifier)
                    .suspendActivate(
                      user.id,
                      isActive ? 'suspend' : 'activate',
                    );
                ref.invalidate(_empDetailProvider(userId));
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
              onPressed: () async {
                await ref.read(hmEmployeeProvider.notifier).archive(user.id);
                if (context.mounted) context.pop();
              },
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Archive'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            ),
          ],
        ),
      ],
    ),
  );
}
