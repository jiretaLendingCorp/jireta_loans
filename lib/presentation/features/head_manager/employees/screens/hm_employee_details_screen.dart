// lib/presentation/features/head_manager/employees/screens/hm_employee_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/details/details_actions_card.dart';
import '../../../../shared/widgets/details/details_section_card.dart';
import '../../../../shared/widgets/details/user_profile_header_card.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
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
              ShimmerLoader(height: 140),
              SizedBox(height: 16),
              ShimmerLoader(height: 200),
            ],
          ),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserProfileHeaderCard(
                photoUrl: user.profilePhotoUrl,
                name:
                    '${user.firstName}${user.middleName != null ? ' ${user.middleName}' : ''} ${user.lastName}',
                subtitle: user.email ?? '—',
                subtitleIcon: Icons.email_outlined,
                roleLabel: 'Employee',
                roleIcon: Icons.badge_outlined,
                accentColor: AppColors.deepNavy,
                accountStatus: user.accountStatus,
              ),
              const SizedBox(height: 20),
              DetailsSectionCard(
                title: 'Account Information',
                icon: Icons.account_circle_outlined,
                accentColor: AppColors.deepNavy,
                items: [
                  const DetailsItem('Role', 'Employee'),
                  DetailsItem('Email', user.email ?? '—'),
                  DetailsItem('Phone', user.phoneNumber ?? '—'),
                  DetailsItem('Position', user.position ?? '—'),
                  DetailsItem('Gender', user.gender ?? '—'),
                  DetailsItem('Civil Status', user.civilStatus ?? '—'),
                  DetailsItem(
                    'Created At',
                    user.createdAt.toString().substring(0, 10),
                  ),
                  DetailsItem(
                    'Last Login',
                    user.lastLoginAt?.toString().substring(0, 16) ?? '—',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              DetailsActionsCard(
                title: 'Actions',
                icon: Icons.settings_outlined,
                accentColor: AppColors.deepNavy,
                actions: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref
                          .read(hmEmployeeProvider.notifier)
                          .archive(user.id);
                      if (context.mounted) context.pop();
                    },
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Archive'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}