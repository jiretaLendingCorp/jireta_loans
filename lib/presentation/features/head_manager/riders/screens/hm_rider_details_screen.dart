// lib/presentation/features/head_manager/riders/screens/hm_rider_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/details/details_actions_card.dart';
import '../../../../shared/widgets/details/details_section_card.dart';
import '../../../../shared/widgets/details/user_profile_header_card.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/hm_rider_provider.dart';

final _riderDetailProvider = FutureProvider.family<UserModel, String>((
  ref,
  id,
) async {
  return sl<UserRemoteDataSource>().getProfile(userId: id);
});

class HmRiderDetailsScreen extends ConsumerWidget {
  final String userId;
  const HmRiderDetailsScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_riderDetailProvider(userId));
    return WebScaffold(
      title: 'Rider Details',
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
                name: '${user.firstName} ${user.lastName}',
                subtitle: user.phoneNumber ?? '—',
                subtitleIcon: Icons.phone_outlined,
                roleLabel: 'Rider',
                roleIcon: Icons.directions_bike_outlined,
                accentColor: AppColors.riderGreen,
                accountStatus: user.accountStatus,
              ),
              const SizedBox(height: 20),
              DetailsSectionCard(
                title: 'Vehicle Information',
                icon: Icons.directions_bike_outlined,
                accentColor: AppColors.riderGreen,
                items: [
                  DetailsItem('Vehicle Type', user.vehicleType ?? '—'),
                  DetailsItem('Vehicle Brand', user.vehicleBrand ?? '—'),
                  DetailsItem('Plate Number', user.plateNumber ?? '—'),
                  DetailsItem(
                      "Driver's License", user.driversLicenseNumber ?? '—'),
                ],
              ),
              const SizedBox(height: 20),
              DetailsSectionCard(
                title: 'Account Information',
                icon: Icons.account_circle_outlined,
                accentColor: AppColors.riderGreen,
                items: [
                  const DetailsItem('Role', 'Rider'),
                  DetailsItem('Phone', user.phoneNumber ?? '—'),
                  DetailsItem('Account Status', user.accountStatus),
                  DetailsItem(
                    'Member Since',
                    user.createdAt.toString().substring(0, 10),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              DetailsActionsCard(
                title: 'Actions',
                icon: Icons.settings_outlined,
                accentColor: AppColors.riderGreen,
                actions: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(hmRiderProvider.notifier).archive(user.id);
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