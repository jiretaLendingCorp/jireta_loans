// lib/presentation/features/rider/profile/screens/rider_profile_screen.dart
// Modern Minimalist redesign: neutral cards, hairline dividers,
// quiet icons, single accent (rider green).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/config/app_config.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_refresh.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
// `kDesktopBreakpoint` — isang breakpoint lang ang buong app para sa desktop
// chrome (sidebar + top bar), kaya dito rin ito sinasalalay ng layout ng body.
import '../../../../shared/widgets/layout/web_scaffold.dart'
    show kDesktopBreakpoint;
import '../../../../shared/widgets/security/mfa_settings_card.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/profile/modern_profile_widgets.dart';
import '../../../../shared/widgets/security/mpin_settings_card.dart';
import '../../../../shared/providers/app_settings_provider.dart';
import '../providers/rider_profile_provider.dart';
import '../widgets/rider_details_dialogs.dart';

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

  /// SILENT reload — walang skeleton flash habang nakabitin ang pull-down
  /// spinner, kaya nananatili rin ang naka-render na profile.
  Future<void> _refresh() =>
      ref.read(riderProfileProvider.notifier).loadProfile(silent: true);

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
              : MobileRefresh(
                  color: _accent,
                  onRefresh: _refresh,
                  child: _buildBody(state),
                ),
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
                  size: 24, color: ModernProfileStyles.iconColorOf(context)),
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
              onPressed: () =>
                  ref.read(riderProfileProvider.notifier).loadProfile(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(RiderProfileState state) {
    final user = state.user;
    final name =
        user != null ? '${user.firstName} ${user.lastName}'.trim() : 'Rider';
    final status = _statusStyle(context, user?.accountStatus);

    // Desktop: dalawang column — kaliwang rail ang identity + account actions,
    // kanang column ang mga section. Sa mobile, isang column pa rin — walang
    // binago sa phone.
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    // ── Identity (header) — ISANG pinagmumulan lang ito, at ang pagkaka-ayos
    // lang ang pinag-iba ng mobile at desktop. ──
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
      ],
    );

    // ── Mga section ng profile (ito ang KANANG column sa desktop) ──
    final sections = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const ModernSectionLabel('Personal'),
        // Pindot-pindot na text lang ang titles — ang mga field (Full name
        // etc.) ay lumalabas sa POPUP at pwedeng i-edit doon, hindi sa ilalim
        // ng title.
        _buildSectionLink('Personal Details', Icons.person_outline_rounded,
            () => showRiderPersonalDetailsDialog(context)),
        const SizedBox(height: 12),
        _buildSectionLink(
            'Email', Icons.email_outlined, () => showRiderEmailDialog(context)),
        const SizedBox(height: 12),
        _buildSectionLink('Rider Information', Icons.two_wheeler_outlined,
            () => showRiderInfoDialog(context)),
        const SizedBox(height: 20),
        const ModernSectionLabel('Appearance & Alerts'),
        Consumer(builder: (context, ref, _) {
          final settings = ref.watch(appSettingsProvider);
          final notifier = ref.read(appSettingsProvider.notifier);
          return ModernMenuCard(flat: true, items: [
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
        // MPIN — 4-digit na pang-kumpirma sa lahat ng submission kapag
        // walang password o biometrics ang phone.
        const ModernSectionLabel('Security'),
        const MpinSettingsCard(flat: true),
        const SizedBox(height: 12),
        // Google Authenticator (TOTP) — second factor sa login, kapareho ng
        // lender: status, enrollment (QR + manual key) at disable dito; ang
        // pagsusuri ng code ay Supabase Auth (`mfa.challenge` /
        // `mfa.verify`).
        const MfaSettingsCard(flat: true),
        const SizedBox(height: 20),
        const ModernSectionLabel('General'),
        ModernMenuCard(flat: true, items: [
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
                  title: 'SMS messages & sender name',
                  body:
                      'One-time passwords and collection notices are sent by SMS under the Sender Name "JiretaLoans", never a shared or unregistered name. As a capstone project, messages are sent only to the project team and volunteer testers who agreed to receive them for the duration of the project.',
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
      ],
    );

    // ── Account actions (bersyon lang) — nasa ilalim ng identity rail sa
    // desktop at sa dulo ng page sa mobile. Ang Log Out ay nasa SIDEBAR na
    // (desktop) / account section, kaya wala nang doble dito.
    final footer = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Version ${AppConfig.appVersion}',
            style: TextStyle(fontSize: 12, color: context.cTextTertiary),
          ),
        ),
      ],
    );

    if (isDesktop) {
      // DESKTOP: kaliwang rail (identity + account actions) at kanang column
      // (mga section) — kaparehong sukat ng dashboard (maxWidth 1240).
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 360,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [identity, footer],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(child: sections),
              ],
            ),
          ),
        ),
      );
    }

    // MOBILE: isang column pa lang (walang binago sa phone).
    return SingleChildScrollView(
      // Laging naka-scrollable: kapag mas maikli sa screen ang profile, walang
      // overscroll kaya hindi gagana ang pull-to-refresh.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [identity, sections, footer],
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
      builder: (_) =>
          ModernInfoSheet(title: title, icon: icon, sections: sections),
    );
  }

  /// Theme-aware status palette — sa dark mode, mas maliwanag na green ang
  /// "Active" para hindi ito maging madilim na teksto sa dark background.
  _StatusStyle _statusStyle(BuildContext context, String? status) {
    final s = (status ?? 'active').toLowerCase();
    return switch (s) {
      'active' =>
        _StatusStyle('Active', context.cBrandGreen, AppColors.successLight),
      'whitelisted' => _StatusStyle(
          'Whitelisted', context.cBrandGreen, AppColors.successLight),
      'suspended' => const _StatusStyle(
          'Suspended', AppColors.warning, AppColors.warningLight),
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

  /// Text lang na pindot-pindot — bubukas ang popup ng section para makita
  /// at ma-edit ang mga field (walang rows sa ilalim, walang arrow).
  Widget _buildSectionLink(String title, IconData icon, VoidCallback onTap) {
    return ModernInfoCard(
      title: title,
      icon: icon,
      rows: const [],
      flat: true,
      onTap: onTap,
    );
  }
}

class _StatusStyle {
  final String label;
  final Color fg;
  final Color bg;
  const _StatusStyle(this.label, this.fg, this.bg);
}
