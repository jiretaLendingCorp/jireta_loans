// lib/presentation/features/rider/profile/screens/rider_profile_screen.dart
// Modern Minimalist redesign: neutral cards, hairline dividers,
// quiet icons, single accent (rider green).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/config/app_config.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/profile/modern_profile_widgets.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../shared/providers/app_settings_provider.dart';
import '../../../../shared/providers/auth_state_provider.dart';
import '../providers/rider_profile_provider.dart';

class RiderProfileScreen extends ConsumerStatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  ConsumerState<RiderProfileScreen> createState() =>
      _RiderProfileScreenState();
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
        icon: Icons.history_outlined,
        activeIcon: Icons.history_rounded,
        label: 'History',
        route: RouteConstants.riderHistory),
    MobileNavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.riderProfile),
  ];

  static const _accent = AppColors.riderGreen;

  void _openEditProfile() =>
      context.push(RouteConstants.riderEditProfile);

  Future<void> _logout() async {
    if (ref.read(authStateProvider).isLoggingOut) return;
    // No confirmation modal. Flow: button loading → logout → success modal
    // steady for 2s → login page. The redirect is held while the modal is up
    // so it can't yank the stack mid-modal.
    AppConstants.suppressLogoutRedirect = true;
    try {
      await ref.read(authProvider.notifier).logout();
    } catch (_) {}
    AppConstants.suppressLogoutRedirect = false;
    if (!mounted || !context.mounted) return;
    await SuccessDialog.showAutoDismiss(
      context,
      title: 'Successfully Logged Out',
      message: 'You have been logged out successfully.',
    );
    if (!mounted || !context.mounted) return;
    context.go(RouteConstants.mobileLogin);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderProfileProvider);

    return MobileScaffold(
      title: 'Profile',
      accentColor: _accent,
      navItems: _navItems,
      body: state.isLoading && state.user == null
          ? _buildSkeleton()
          : state.error != null && state.user == null
              ? _buildError(state.error!)
              : _buildBody(state),
    );
  }

  /// Skeletal (shimmer) loading para sa Profile — kaparehong itsura ng
  /// tunay na screen imbes na spinner.
  Widget _buildSkeleton() {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + pangalan + status
          Center(
            child: Column(
              children: [
                ShimmerLoader(width: 76, height: 76, borderRadius: 38),
                SizedBox(height: 12),
                ShimmerLoader(width: 150, height: 18),
                SizedBox(height: 8),
                ShimmerLoader(width: 70, height: 12),
              ],
            ),
          ),
          SizedBox(height: 18),
          Center(child: ShimmerLoader(width: 92, height: 14)),
          SizedBox(height: 22),
          ShimmerLoader(width: 80, height: 12),
          SizedBox(height: 10),
          SkeletonCard(),
          SizedBox(height: 12),
          SkeletonCard(),
          SizedBox(height: 20),
          ShimmerLoader(width: 130, height: 12),
          SizedBox(height: 10),
          SkeletonCard(),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: ModernProfileStyles.iconBgOf(context),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.person_off_outlined,
                  size: 24,
                  color: ModernProfileStyles.iconColorOf(context)),
            ),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: ModernProfileStyles.subOf(context)),
            const SizedBox(height: 16),
            ModernPrimaryButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              color: _accent,
              onPressed: () => ref
                  .read(riderProfileProvider.notifier)
                  .loadProfile(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(RiderProfileState state) {
    final user = state.user;
    final name = user != null
        ? '${user.firstName} ${user.lastName}'.trim()
        : 'Rider';
    final status = _statusStyle(context, user?.accountStatus);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ModernProfileHeader(
            name: name.isEmpty ? 'Rider' : name,
            subtitles: const [],
            // Walang card sa likod ng avatar/name/status — nakalapat lang sa
            // page (flat) gaya ng request.
            flat: true,
            photoUrl: user?.profilePhotoUrl,
            // Theme-aware accent: ang initials sa avatar ay hindi dapat maging
            // madilim na green sa dark mode.
            accent: context.cBrandGreen,
            onAvatarUploaded: _updateAvatar,
            statusLabel: status.label,
            statusColor: status.fg,
            statusBg: status.bg,
            statusAsText: true,
          ),
          const SizedBox(height: 16),
          // Text lang (hindi button) — payak na link pababa sa Edit Profile.
          // `cBrandGreen` para manatiling nababasa sa dark mode (mas
          // maliwanag na green), hindi ang static na riderGreen.
          Center(
            child: TextButton.icon(
              onPressed: _openEditProfile,
              icon: Icon(Icons.edit_outlined,
                  size: 16, color: context.cBrandGreen),
              label: Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.cBrandGreen,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const ModernSectionLabel('Personal'),
          _buildPersonalCard(state),
          const SizedBox(height: 12),
          _buildRiderCard(state),
          const SizedBox(height: 20),
          const ModernSectionLabel('Appearance & Alerts'),
          Consumer(builder: (context, ref, _) {
            final settings = ref.watch(appSettingsProvider);
            final notifier = ref.read(appSettingsProvider.notifier);
            return ModernMenuCard(items: [
              ModernMenuItem(
                icon: Icons.dark_mode_outlined,
                title: 'Dark Mode',
                subtitle: settings.isDark
                    ? 'On — dark theme is active'
                    : (settings.themeMode == ThemeMode.system
                        ? 'Off — following system setting'
                        : 'Off — light theme'),
                onTap: () => notifier.setDarkMode(!settings.isDark),
                trailing: Switch.adaptive(
                  value: settings.isDark,
                  activeTrackColor: context.cBrandGreen,
                  onChanged: (v) => notifier.setDarkMode(v),
                ),
              ),
              ModernMenuItem(
                icon: Icons.notifications_active_outlined,
                title: 'Push Notifications',
                subtitle: settings.pushNotificationsEnabled
                    ? 'On — alerts are sent to this device'
                    : 'Off — no push alerts on this device',
                onTap: () => notifier
                    .setPushNotifications(!settings.pushNotificationsEnabled),
                trailing: Switch.adaptive(
                  value: settings.pushNotificationsEnabled,
                  activeTrackColor: context.cBrandGreen,
                  onChanged: (v) => notifier.setPushNotifications(v),
                ),
              ),
            ]);
          }),
          const SizedBox(height: 20),
          const ModernSectionLabel('General'),
          ModernMenuCard(items: [
            ModernMenuItem(
              icon: Icons.description_outlined,
              title: 'Terms & Conditions',
              subtitle: 'Review the terms of service',
              onTap: () => _showSheet(
                title: 'Terms & Conditions',
                icon: Icons.description_outlined,
                sections: const [
                  ModernSheetSection(
                    title: 'Your responsibilities',
                    body:
                        'Perform credit investigations and cash collections professionally, safeguard lender information, and follow schedules given by authorized personnel.',
                  ),
                  ModernSheetSection(
                    title: 'Data privacy',
                    body:
                        'Lender and company information must be kept confidential and used only for official duties, under the Data Privacy Act of 2012 (RA 10173).',
                  ),
                  ModernSheetSection(
                    title: 'Prohibited acts',
                    body:
                        'Do not collect more than the amount shown, tamper with evidence or signatures, or use company resources for personal gain.',
                  ),
                ],
              ),
            ),
            ModernMenuItem(
              icon: Icons.support_agent_outlined,
              title: 'Help Center',
              subtitle: 'FAQs and support guide',
              onTap: () => _showSheet(
                title: 'Help Center',
                icon: Icons.support_agent_outlined,
                sections: const [
                  ModernSheetSection(
                    title: 'How do I accept a collection?',
                    body:
                        'Open the Assigned item in Collections, review the details, then tap Accept. Navigate to the lender and record the collection.',
                  ),
                  ModernSheetSection(
                    title: 'How do I record a collection?',
                    body:
                        'Enter the amount and notes, then upload proof photos and signature. Your location is captured automatically.',
                  ),
                  ModernSheetSection(
                    title: 'What if I cannot find the lender?',
                    body:
                        'Use Navigate to open Maps. If still unreachable, contact support or decline with a reason so it can be reassigned.',
                  ),
                ],
              ),
            ),
            ModernMenuItem(
              icon: Icons.info_outline_rounded,
              title: 'About Jireta',
              subtitle: 'Learn more about our company',
              onTap: () => _showSheet(
                title: 'About Jireta',
                icon: Icons.info_outline_rounded,
                sections: const [
                  ModernSheetSection(
                    title: 'Company',
                    body:
                        'Jireta Loans & Credit Corp 1966 provides financial assistance to Filipinos.',
                  ),
                  ModernSheetSection(
                    title: 'Your role',
                    body:
                        'As a rider you handle cash collections and credit investigations, ensuring every transaction is recorded and receipted.',
                  ),
                ],
              ),
            ),
            ModernMenuItem(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              subtitle: 'How we protect your data',
              onTap: () => _showSheet(
                title: 'Privacy Policy',
                icon: Icons.privacy_tip_outlined,
                sections: const [
                  ModernSheetSection(
                    title: 'Data we collect',
                    body:
                        'We collect your personal and vehicle details, license, location during active tasks, and transaction proofs.',
                  ),
                  ModernSheetSection(
                    title: 'How we use your data',
                    body:
                        'Your data is used only for collection verification, CI reports, and audit trails.',
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Consumer(builder: (context, ref, _) {
            final isLoggingOut = ref.watch(
                authStateProvider.select((s) => s.isLoggingOut));
            return SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: isLoggingOut ? null : _logout,
                icon: isLoggingOut
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2))
                    : const Icon(Icons.logout_rounded,
                        size: 18, color: AppColors.error),
                label: Text(
                  isLoggingOut ? 'Logging out…' : 'Log out',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: context.isDarkMode
                          ? AppColors.error.withValues(alpha: 0.35)
                          : const Color(0xFFF0CFCF)),
                  backgroundColor: context.cSurface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Version ${AppConfig.appVersion}',
              style: TextStyle(
                  fontSize: 12, color: context.cTextTertiary),
            ),
          ),
        ],
      ),
    );
  }

  void _showSheet({
    required String title,
    required IconData icon,
    required List<ModernSheetSection> sections,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ModernInfoSheet(
          title: title, icon: icon, sections: sections),
    );
  }

  /// Theme-aware status palette — sa dark mode, mas maliwanag na green ang
  /// "Active" para hindi ito maging madilim na teksto sa dark background.
  _StatusStyle _statusStyle(BuildContext context, String? status) {
    final s = (status ?? 'active').toLowerCase();
    return switch (s) {
      'active' => _StatusStyle(
          'Active', context.cBrandGreen, AppColors.successLight),
      'whitelisted' => _StatusStyle(
          'Whitelisted', context.cBrandGreen, AppColors.successLight),
      'suspended' => const _StatusStyle('Suspended', AppColors.warning,
          AppColors.warningLight),
      'blacklisted' || 'deactivated' => _StatusStyle(
          s[0].toUpperCase() + s.substring(1),
          AppColors.error,
          AppColors.errorLight),
      _ => _StatusStyle(status ?? 'Active', context.cTextSecondary,
          ModernProfileStyles.iconBgOf(context)),
    };
  }

  Future<void> _updateAvatar(String url) async {
    final ok = await ref.read(riderProfileProvider.notifier).updateProfile({
      'profile_photo_url': url,
    });
    if (mounted && ok) {
      await ref.read(riderProfileProvider.notifier).refresh();
    }
  }

  Widget _buildPersonalCard(RiderProfileState state) {
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
    return ModernInfoCard(
      title: 'Personal Details',
      icon: Icons.person_outline_rounded,
      collapsible: true,
      initiallyExpanded: false,
      rows: [
        ModernInfoRowData(
            icon: Icons.person_outline_rounded,
            label: 'Full name',
            value: fullName.isEmpty ? '—' : fullName),
        ModernInfoRowData(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: phone.isEmpty ? '—' : phone),
        ModernInfoRowData(
            icon: Icons.email_outlined,
            label: 'Email',
            value: email.isEmpty ? '—' : email),
        ModernInfoRowData(
            icon: Icons.calendar_today_outlined,
            label: 'Member since',
            value: _memberSince(user)),
      ],
    );
  }

  Widget _buildRiderCard(RiderProfileState state) {
    final user = state.user;
    if (user == null) return const SizedBox();
    final plate = (user.plateNumber ?? '').toString();
    final license = (user.driversLicenseNumber ?? '').toString();
    final brand = (user.vehicleBrand ?? '').toString();
    final type = (user.vehicleType ?? '').toString();
    return ModernInfoCard(
      title: 'Rider Information',
      icon: Icons.two_wheeler_outlined,
      collapsible: true,
      initiallyExpanded: false,
      rows: [
        ModernInfoRowData(
            icon: Icons.confirmation_number_outlined,
            label: 'Plate number',
            value: plate.isEmpty ? '—' : plate),
        ModernInfoRowData(
            icon: Icons.card_membership_outlined,
            label: 'License number',
            value: license.isEmpty ? '—' : license),
        ModernInfoRowData(
            icon: Icons.two_wheeler_outlined,
            label: 'Vehicle brand',
            value: brand.isEmpty ? '—' : _formatLabel(brand)),
        ModernInfoRowData(
            icon: Icons.category_outlined,
            label: 'Vehicle type',
            value: type.isEmpty ? '—' : _formatLabel(type)),
      ],
    );
  }

  String _memberSince(dynamic user) {
    try {
      final dynamic ca = (user as dynamic).createdAt;
      DateTime? dt;
      if (ca is DateTime) {
        dt = ca;
      } else if (ca is String) {
        dt = DateTime.tryParse(ca);
        if (dt == null && ca.isNotEmpty) return ca;
      } else if (ca != null) {
        dt = DateTime.tryParse(ca.toString());
      }
      if (dt == null) return '—';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '—';
    }
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
}

class _StatusStyle {
  final String label;
  final Color fg;
  final Color bg;
  const _StatusStyle(this.label, this.fg, this.bg);
}
