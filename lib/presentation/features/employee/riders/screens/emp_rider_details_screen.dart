// lib/presentation/features/employee/riders/screens/emp_rider_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/profile_avatar.dart';

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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ProfileAvatar(
                        photoUrl: data['profile_photo_url'] as String?,
                        name: (data['first_name'] as String? ?? ''),
                        color: AppColors.riderGreen,
                        radius: 32,
                        fallback: const Icon(Icons.directions_bike,
                            color: AppColors.riderGreen, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'
                                    .trim(),
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            Text(data['phone_number'] ?? data['phone'] ?? '—',
                                style: const TextStyle(
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      StatusBadge(status: data['account_status'] ?? 'active'),
                    ],
                  ),
                  const Divider(height: 28),
                  const Text('Rider Information',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepNavy)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 16, runSpacing: 12, children: [
                    _infoTile('Vehicle Type', profile?['vehicle_type'] ?? '—'),
                    _infoTile('Plate Number', profile?['plate_number'] ?? '—'),
                    _infoTile("Driver's License",
                        profile?['drivers_license_number'] ?? '—'),
                    _infoTile('License Expiry',
                        profile?['drivers_license_expiry'] ?? '—'),
                    _infoTile(
                        'Vehicle Brand', profile?['vehicle_brand'] ?? '—'),
                    _infoTile(
                        'Availability',
                        profile?['is_available'] == true
                            ? 'Available'
                            : 'On Duty'),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
