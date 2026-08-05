// lib/presentation/features/rider/profile/screens/rider_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../auth/providers/auth_provider.dart';
import '../providers/rider_profile_provider.dart';

class RiderProfileScreen extends ConsumerStatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  ConsumerState<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends ConsumerState<RiderProfileScreen> {
  static const _navItems = [
    MobileNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: RouteConstants.riderDashboard),
    MobileNavItem(
        icon: Icons.payments_outlined,
        activeIcon: Icons.payments,
        label: 'Collections',
        route: RouteConstants.riderCollections),
    MobileNavItem(
        icon: Icons.search_outlined,
        activeIcon: Icons.search,
        label: 'CI Tasks',
        route: RouteConstants.riderCi),
    MobileNavItem(
        icon: Icons.notifications_outlined,
        activeIcon: Icons.notifications,
        label: 'Notifications',
        route: RouteConstants.riderNotifications),
    MobileNavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.riderProfile),
  ];

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  bool _populated = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _plateCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  void _populate(state) {
    if (_populated || state.user == null) return;
    _firstCtrl.text = state.user!.firstName;
    _lastCtrl.text = state.user!.lastName;
    _plateCtrl.text = state.plateNumber ?? '';
    _licenseCtrl.text = state.licenseNumber ?? '';
    _populated = true;
  }

  Future<void> _save() async {
    final notifier = ref.read(riderProfileProvider.notifier);
    final ok = await notifier.update({
      'first_name': _firstCtrl.text.trim(),
      'last_name': _lastCtrl.text.trim(),
      'plate_number': _plateCtrl.text.trim(),
      'drivers_license_number': _licenseCtrl.text.trim(),
    });
    if (!mounted) return;
    if (ok) {
      showDialog(
          context: context,
          builder: (_) =>
              const SuccessDialog(message: 'Profile updated successfully'));
    } else {
      showDialog(
          context: context,
          builder: (_) =>
              const ErrorDialog(message: 'Failed to update profile'));
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderProfileProvider);
    _populate(state);

    return MobileScaffold(
      title: 'My Profile',
      accentColor: AppColors.riderGreen,
      navItems: _navItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildAvatar(state),
                  const SizedBox(height: 24),
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  _buildRiderInfoCard(),
                  const SizedBox(height: 16),
                  AppButton(
                    label: state.isSaving ? 'Saving...' : 'Save Changes',
                    onPressed: state.isSaving ? null : _save,
                    color: AppColors.riderGreen,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, color: AppColors.error),
                    label: const Text('Sign Out',
                        style: TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.error),
                        minimumSize: const Size(double.infinity, 48)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildAvatar(state) {
    final name = state.user != null
        ? '${state.user!.firstName} ${state.user!.lastName}'
        : 'Rider';
    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: AppColors.riderGreen.withValues(alpha: 0.15),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'R',
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: AppColors.riderGreen),
          ),
        ),
        const SizedBox(height: 12),
        Text(name,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: AppColors.riderGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: const Text('Rider',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.riderGreen,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Personal Information',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            AppTextField(controller: _firstCtrl, label: 'First Name'),
            const SizedBox(height: 12),
            AppTextField(controller: _lastCtrl, label: 'Last Name'),
          ],
        ),
      ),
    );
  }

  Widget _buildRiderInfoCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rider Information',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            AppTextField(controller: _plateCtrl, label: 'Plate Number'),
            const SizedBox(height: 12),
            AppTextField(
                controller: _licenseCtrl, label: "Driver's License Number"),
          ],
        ),
      ),
    );
  }

}
