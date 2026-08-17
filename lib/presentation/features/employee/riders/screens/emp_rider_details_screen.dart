// lib/presentation/features/employee/riders/screens/emp_rider_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../shared/widgets/details/details_section_card.dart';
import '../../../../shared/widgets/details/user_profile_header_card.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';

final _empRiderDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return await sl<UserRemoteDataSource>().getProfileMap(userId: id);
});

class EmpRiderDetailsScreen extends ConsumerWidget {
  final String riderId;
  const EmpRiderDetailsScreen({super.key, required this.riderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_empRiderDetailProvider(riderId));

    return WebScaffold(
      title: 'Rider Details',
      body: state.when(
        loading: () => _buildShimmer(),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (data) => _buildContent(data),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final profile = data['rider_profiles'] as Map<String, dynamic>?;
    final name =
        '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserProfileHeaderCard(
            photoUrl: data['profile_photo_url'] as String?,
            name: name.isEmpty ? 'Rider' : name,
            subtitle: data['phone_number'] ?? data['phone'] ?? '—',
            subtitleIcon: Icons.phone_outlined,
            roleLabel: 'Rider',
            roleIcon: Icons.directions_bike_outlined,
            accentColor: AppColors.riderGreen,
            accountStatus: data['account_status'] ?? 'active',
          ),
          const SizedBox(height: 20),
          DetailsSectionCard(
            title: 'Vehicle Information',
            icon: Icons.directions_bike_outlined,
            accentColor: AppColors.riderGreen,
            items: [
              DetailsItem('Vehicle Type', profile?['vehicle_type'] ?? '—'),
              DetailsItem('Vehicle Brand', profile?['vehicle_brand'] ?? '—'),
              DetailsItem('Plate Number', profile?['plate_number'] ?? '—'),
              DetailsItem(
                  "Driver's License",
                  profile?['drivers_license_number'] ?? '—'),
              DetailsItem(
                  'License Expiry', profile?['drivers_license_expiry'] ?? '—'),
              DetailsItem(
                'Availability',
                profile?['is_available'] == true ? 'Available' : 'On Duty',
              ),
            ],
          ),
          const SizedBox(height: 20),
          DetailsSectionCard(
            title: 'Account Information',
            icon: Icons.account_circle_outlined,
            accentColor: AppColors.riderGreen,
            items: [
              DetailsItem('Account Status', data['account_status'] ?? '—'),
              DetailsItem(
                'Member Since',
                (data['created_at'] ?? '').toString().substring(0, 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() => ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: 2,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, __) => const ShimmerLoader(height: 200),
      );
}