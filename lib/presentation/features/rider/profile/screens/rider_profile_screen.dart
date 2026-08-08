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
import '../../../../shared/widgets/profile_avatar_upload.dart';
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
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.riderProfile),
  ];

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
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
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(riderProfileProvider.notifier);
    final ok = await notifier.update({
      'first_name': _firstCtrl.text.trim(),
      'last_name': _lastCtrl.text.trim(),
      'rider_profile': {
        'plate_number': _plateCtrl.text.trim(),
        'drivers_license_number': _licenseCtrl.text.trim(),
      },
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
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(state),
                    const SizedBox(height: 22),
                    _sectionTitle('Personal Information'),
                    const SizedBox(height: 10),
                    _buildFieldCard([
                      AppTextField(
                        controller: _firstCtrl,
                        label: 'First Name',
                        prefixIcon: Icons.person_outline,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'First name is required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _lastCtrl,
                        label: 'Last Name',
                        prefixIcon: Icons.person_outline,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Last name is required'
                            : null,
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _sectionTitle('Rider Information'),
                    const SizedBox(height: 10),
                    _buildFieldCard([
                      AppTextField(
                        controller: _plateCtrl,
                        label: 'Plate Number',
                        prefixIcon: Icons.directions_bike_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Plate number is required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _licenseCtrl,
                        label: "Driver's License Number",
                        prefixIcon: Icons.badge_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? "Driver's license number is required"
                            : null,
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _sectionTitle('Account'),
                    const SizedBox(height: 10),
                    _buildLegalCard(),
                    const SizedBox(height: 22),
                    AppButton(
                      label: state.isSaving ? 'Saving...' : 'Save Changes',
                      onPressed: state.isSaving ? null : _save,
                      color: AppColors.riderGreen,
                      isExpanded: true,
                      icon: Icons.save_outlined,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout, color: AppColors.error),
                      label: const Text('Sign Out',
                          style: TextStyle(color: AppColors.error)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.error),
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(state) {
    final user = state.user;
    final name =
        user != null ? '${user.firstName} ${user.lastName}' : 'Rider';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.riderGreen, AppColors.riderGreenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.riderGreen.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _statusPill(user?.accountStatus),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: ProfileAvatarUpload(
              photoUrl: user?.profilePhotoUrl,
              name: name,
              color: AppColors.riderGreen,
              radius: 38,
              onUploaded: _updateAvatar,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _roleChip(Icons.directions_bike, 'Rider'),
              const SizedBox(width: 8),
              _roleChip(Icons.verified_outlined, 'CI Collector'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Tap the camera icon to change your profile picture',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String? status) {
    final s = (status ?? 'active').toLowerCase();
    final label = switch (s) {
      'active' => 'Active',
      'suspended' => 'Suspended',
      'blacklisted' => 'Blacklisted',
      'deactivated' => 'Deactivated',
      _ => (status ?? 'Active'),
    };
    final color = switch (s) {
      'active' => AppColors.success,
      'suspended' => AppColors.warning,
      'blacklisted' || 'deactivated' => AppColors.error,
      _ => AppColors.goldLight,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _roleChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold, width: 1),
        borderRadius: BorderRadius.circular(20),
        color: AppColors.gold.withValues(alpha: 0.15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.goldLight),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.goldLight),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.deepNavy,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Future<void> _updateAvatar(String url) async {
    final ok = await ref.read(riderProfileProvider.notifier).updateProfile({
      'profile_photo_url': url,
    });
    if (mounted && ok) {
      await ref.read(riderProfileProvider.notifier).refresh();
    }
  }

  Widget _buildLegalCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: AppColors.riderGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.description_outlined,
              color: AppColors.riderGreen, size: 22),
        ),
        title: const Text('Terms & Conditions',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.deepNavy)),
        subtitle: const Text('Review the terms of service',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _RiderTermsSheet(),
        ),
      ),
    );
  }

}

class _RiderTermsSheet extends StatelessWidget {
  const _RiderTermsSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.description_outlined,
                    color: AppColors.gold, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Terms & Conditions',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RiderTermSection(
                    title: '1. Agreement to Terms',
                    body:
                        'By accessing and using the Jireta Loans & Credit Corp 1966 mobile application, you agree to be bound by these Terms and Conditions and our Privacy Policy.',
                  ),
                  _RiderTermSection(
                    title: '2. Responsibilities of Riders',
                    body:
                        'As an assigned rider you agree to perform credit investigations and cash collections professionally, safeguard borrower information, and follow the schedules and instructions given by authorized personnel.',
                  ),
                  _RiderTermSection(
                    title: '3. Data Privacy',
                    body:
                        'Borrower and company information you access must be kept confidential and used only for official duties, in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173).',
                  ),
                  _RiderTermSection(
                    title: '4. Prohibited Acts',
                    body:
                        'You agree not to collect more than the amount shown in the system, tamper with evidence or signatures, or use company resources for personal gain. Violations may result in suspension or termination.',
                  ),
                  _RiderTermSection(
                    title: '5. Governing Law',
                    body:
                        'These terms are governed by the laws of the Republic of the Philippines.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderTermSection extends StatelessWidget {
  final String title;
  final String body;
  const _RiderTermSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.deepNavy),
          ),
        ),
        Text(
          body,
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary, height: 1.6),
        ),
      ],
    );
  }
}
