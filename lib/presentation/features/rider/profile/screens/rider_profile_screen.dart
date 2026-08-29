// lib/presentation/features/rider/profile/screens/rider_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/config/app_config.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/profile_avatar_upload.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../shared/providers/auth_state_provider.dart';
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

  int _expandedSection = -1;

  void _openEditProfile() => context.push(RouteConstants.riderEditProfile);

  Future<void> _logout() async {
    if (ref.read(authStateProvider).isLoggingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Do you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Global [LogoutOverlay] shows "Logging out..." automatically via
      // authStateProvider.isLoggingOut; keeps rider UX consistent with web.
      await ref.read(authProvider.notifier).logout();
      if (mounted && context.mounted) {
        context.go(RouteConstants.mobileLogin);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderProfileProvider);

    return MobileScaffold(
      title: 'My Profile',
      accentColor: AppColors.riderGreen,
      navItems: _navItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(state),
                  const SizedBox(height: 18),
                  AppButton(
                    label: 'Edit Profile',
                    onPressed: _openEditProfile,
                    color: AppColors.riderGreen,
                    isExpanded: true,
                    icon: Icons.edit_outlined,
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle('Personal Information'),
                  const SizedBox(height: 10),
                  _buildPersonalSection(state),
                  const SizedBox(height: 12),
                  _buildRiderSection(state),
                  const SizedBox(height: 22),
                  _sectionTitle('Account'),
                  const SizedBox(height: 10),
                  _buildLegalCard(),
                  const SizedBox(height: 22),
                  _sectionTitle('Support'),
                  const SizedBox(height: 10),
                  _buildSupportCard(context),
                  const SizedBox(height: 22),
                  const Center(
                    child: Text(
                      'Version ${AppConfig.appVersion}',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Consumer(builder: (context, ref, _) {
                    final isLoggingOut =
                        ref.watch(authStateProvider.select((s) => s.isLoggingOut));
                    return OutlinedButton.icon(
                      onPressed: isLoggingOut ? null : _logout,
                      icon: isLoggingOut
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.error),
                            )
                          : const Icon(Icons.logout, color: AppColors.error),
                      label: Text(
                          isLoggingOut ? 'Logging out...' : 'Log Out',
                          style: const TextStyle(color: AppColors.error)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.error),
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(RiderProfileState state) {
    final user = state.user;
    final name = user != null ? '${user.firstName} ${user.lastName}' : 'Rider';
    final phone = (user?.phoneNumber ?? '').toString();
    final email = (user?.email ?? '').toString();
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _statusPill(user?.accountStatus),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.riderGreen, width: 3),
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
            color: AppColors.riderGreen,
          ),
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            AppFormatters.maskPhone(phone),
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
        if (email.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            email,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
        const SizedBox(height: 6),
        const Text(
          'Tap the camera icon to change your profile picture',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _statusPill(String? status) {
    final s = (status ?? 'active').toLowerCase();
    final label = switch (s) {
      'active' => 'Active',
      'suspended' => 'Suspended',
      'blacklisted' => 'Blacklisted',
      'whitelisted' => 'Whitelisted',
      'deactivated' => 'Deactivated',
      _ => (status ?? 'Active'),
    };
    final color = switch (s) {
      'active' => AppColors.success,
      'suspended' => AppColors.warning,
      'blacklisted' || 'deactivated' => AppColors.error,
      'whitelisted' => AppColors.success,
      _ => AppColors.goldLight,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.riderGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.riderGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.riderGreen),
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

  Future<void> _updateAvatar(String url) async {
    final ok = await ref.read(riderProfileProvider.notifier).updateProfile({
      'profile_photo_url': url,
    });
    if (mounted && ok) {
      await ref.read(riderProfileProvider.notifier).refresh();
    }
  }

  Widget _buildPersonalSection(RiderProfileState state) {
    final user = state.user;
    if (user == null) return const SizedBox();
    final phone = (user.phoneNumber ?? '').toString();
    final email = (user.email ?? '').toString();
    final fullName = [
      user.firstName,
      user.middleName,
      user.lastName,
      user.suffix
    ].where((e) => e != null && e.toString().isNotEmpty).join(' ');
    // Defensive: handle both DateTime and String to avoid
    // NoSuchMethodError: Class 'String' has no instance getter 'year'
    String joined = '—';
    try {
      final dynamic ca = (user as dynamic).createdAt;
      if (ca is DateTime) {
        joined =
            '${ca.year}-${ca.month.toString().padLeft(2, '0')}-${ca.day.toString().padLeft(2, '0')}';
      } else if (ca is String) {
        final dt = DateTime.tryParse(ca);
        if (dt != null) {
          joined =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        } else if (ca.isNotEmpty) {
          joined = ca;
        }
      } else if (ca != null) {
        final dt = DateTime.tryParse(ca.toString());
        if (dt != null) {
          joined =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
      }
    } catch (_) {
      joined = '—';
    }
    return _CollapsibleSection(
      icon: Icons.person_outline,
      title: 'Personal Details',
      isExpanded: _expandedSection == 0,
      onToggle: () =>
          setState(() => _expandedSection = _expandedSection == 0 ? -1 : 0),
      children: [
        _infoRow(Icons.person, 'Full Name', fullName.isEmpty ? '—' : fullName),
        _infoRow(Icons.phone, 'Phone',
            phone.isEmpty ? '—' : AppFormatters.maskPhone(phone)),
        _infoRow(Icons.email_outlined, 'Email',
            email.isEmpty ? '—' : email),
        _infoRow(Icons.badge_outlined, 'Role',
            _formatLabel(user.role)),
        _infoRow(Icons.calendar_today_outlined, 'Member Since', joined),
      ],
    );
  }

  Widget _buildRiderSection(RiderProfileState state) {
    final user = state.user;
    if (user == null) return const SizedBox();
    final plate = (user.plateNumber ?? '').toString();
    final license = (user.driversLicenseNumber ?? '').toString();
    final brand = (user.vehicleBrand ?? '').toString();
    final type = (user.vehicleType ?? '').toString();
    return _CollapsibleSection(
      icon: Icons.directions_bike_outlined,
      title: 'Rider Information',
      isExpanded: _expandedSection == 1,
      onToggle: () =>
          setState(() => _expandedSection = _expandedSection == 1 ? -1 : 1),
      children: [
        _infoRow(Icons.confirmation_number_outlined, 'Plate Number',
            plate.isEmpty ? '—' : plate),
        _infoRow(Icons.card_membership_outlined, 'License Number',
            license.isEmpty ? '—' : license),
        _infoRow(Icons.two_wheeler_outlined, 'Vehicle Brand',
            brand.isEmpty ? '—' : _formatLabel(brand)),
        _infoRow(Icons.category_outlined, 'Vehicle Type',
            type.isEmpty ? '—' : _formatLabel(type)),
        _infoRow(Icons.verified_user_outlined, 'Account Status',
            _formatLabel(user.accountStatus)),
      ],
    );
  }

  String _formatLabel(dynamic value) {
    if (value == null || value.toString().isEmpty) return '—';
    final s = value.toString();
    return s
        .split('_')
        .map((w) => w.isEmpty
            ? w
            : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
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

  Widget _buildSupportCard(BuildContext context) {
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
      child: Column(children: [
        ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.support_agent,
                color: AppColors.riderGreen, size: 22),
          ),
          title: const Text('Help Center',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy)),
          subtitle: const Text('FAQs and support guide',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () => _showHelpSheet(context),
        ),
        const Divider(height: 1, color: AppColors.border),
        ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.info_outline,
                color: AppColors.riderGreen, size: 22),
          ),
          title: const Text('About Jireta',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy)),
          subtitle: const Text('Learn more about our company',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () => _showAboutSheet(context),
        ),
        const Divider(height: 1, color: AppColors.border),
        ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.privacy_tip_outlined,
                color: AppColors.riderGreen, size: 22),
          ),
          title: const Text('Privacy Policy',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy)),
          subtitle: const Text('How we protect your data',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () => _showPrivacySheet(context),
        ),
      ]),
    );
  }

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RiderInfoSheet(
        title: 'Help Center',
        icon: Icons.support_agent,
        sections: [
          _InfoSection(
            title: 'How do I accept a collection?',
            body:
                'Go to Collections tab, open the Assigned item, review lender details, then tap Accept. Once accepted, you can navigate to the lender and record the collection.',
          ),
          _InfoSection(
            title: 'How do I record a collection?',
            body:
                'After accepting, go to Collect tab, enter the amount collected and notes, then upload proof photos and signature to complete. Your GPS is captured automatically.',
          ),
          _InfoSection(
            title: 'What is a CI task?',
            body:
                'Credit Investigation tasks require you to visit the borrower, verify documents and residence, take photos, and submit a report for approval.',
          ),
          _InfoSection(
            title: 'What if I cannot find the lender?',
            body:
                'Use the Navigate button to open Google Maps. If still unreachable, contact support or decline with a reason so it can be reassigned.',
          ),
        ],
      ),
    );
  }

  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RiderInfoSheet(
        title: 'About Jireta',
        icon: Icons.info_outline,
        sections: [
          _InfoSection(
            title: 'Company',
            body:
                'Jireta Loans & Credit Corp 1966 is a lending company offering financial assistance to Filipinos.',
          ),
          _InfoSection(
            title: 'Your Role as Rider',
            body:
                'As a Rider you are a field agent responsible for accurate cash collections and credit investigations, safeguarding lender information and following schedules given by authorized personnel.',
          ),
          _InfoSection(
            title: 'Our Commitment',
            body:
                'We provide fast, secure and convenient services through the mobile app, ensuring every transaction is recorded and receipts are issued.',
          ),
        ],
      ),
    );
  }

  void _showPrivacySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RiderInfoSheet(
        title: 'Privacy Policy',
        icon: Icons.privacy_tip_outlined,
        sections: [
          _InfoSection(
            title: 'Data We Collect',
            body:
                'We collect your personal information, vehicle details, license, location during active tasks, and transaction proofs. Lender information you access must be kept confidential per Data Privacy Act of 2012 (RA 10173).',
          ),
          _InfoSection(
            title: 'How We Use Your Data',
            body:
                'Your data is used only for collection verification, CI reports, and audit trails. Location is tracked only when you have an accepted collection/CI/delivery.',
          ),
          _InfoSection(
            title: 'Your Rights',
            body:
                'You have the right to access, correct, and request deletion of your data in accordance with the Data Privacy Act.',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.riderGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 17, color: AppColors.riderGreen),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
            ])),
      ]),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _CollapsibleSection({
    required this.icon,
    required this.title,
    required this.children,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.riderGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 17, color: AppColors.riderGreen),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepNavy,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Column(
                    children: [
                      const Divider(height: 1, color: AppColors.border),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Column(children: children),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _RiderInfoSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_InfoSection> sections;
  const _RiderInfoSheet(
      {required this.title, required this.icon, required this.sections});

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
              color: AppColors.riderGreen,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sections
                    .map((s) => _InfoSectionWidget(section: s))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection {
  final String title;
  final String body;
  const _InfoSection({required this.title, required this.body});
}

class _InfoSectionWidget extends StatelessWidget {
  final _InfoSection section;
  const _InfoSectionWidget({required this.section});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(
            section.title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.deepNavy),
          ),
        ),
        Text(
          section.body,
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary, height: 1.6),
        ),
      ],
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
                        'As an assigned rider you agree to perform credit investigations and cash collections professionally, safeguard lender information, and follow the schedules and instructions given by authorized personnel.',
                  ),
                  _RiderTermSection(
                    title: '3. Data Privacy',
                    body:
                        'Lender and company information you access must be kept confidential and used only for official duties, in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173).',
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
