// lib/presentation/features/lender/profile/screens/lender_profile_screen.dart
// Modern Minimalist redesign: neutral cards, hairline dividers,
// quiet icons, single accent (lender navy). No serif, no heavy shadows.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/config/app_config.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../shared/widgets/layout/mobile_refresh.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
// `kDesktopBreakpoint` — isang breakpoint lang ang buong app para sa desktop
// chrome (sidebar + top bar), kaya dito rin ito sinasalalay ng layout ng body.
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/legal_links.dart';
import '../../../../shared/widgets/profile/modern_profile_widgets.dart';
import '../../../../shared/widgets/security/mfa_settings_card.dart';
import '../../../../shared/widgets/security/mpin_settings_card.dart';
import '../../../../shared/providers/app_settings_provider.dart';
import '../../../../shared/providers/auth_state_provider.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../auth/providers/auth_provider.dart';
import '../providers/lender_profile_provider.dart';
import '../widgets/lender_details_dialogs.dart';

class LenderProfileScreen extends ConsumerStatefulWidget {
  const LenderProfileScreen({super.key});
  @override
  ConsumerState<LenderProfileScreen> createState() =>
      _LenderProfileScreenState();
}

class _LenderProfileScreenState extends ConsumerState<LenderProfileScreen> {
  static const _navItems = [
    MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard,
    ),
    MobileNavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Payments',
      route: RouteConstants.lenderPayments,
    ),
    MobileNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Transaction',
      route: RouteConstants.lenderPaymentHistory,
    ),
    MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile,
    ),
  ];

  static const _accent = AppColors.lenderBlue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lenderProfileProvider.notifier).loadProfile();
    });
  }

  /// SILENT reload — walang skeleton flash habang nakabitin ang pull-down
  /// spinner, kaya nananatili rin ang naka-render na profile.
  Future<void> _refresh() =>
      ref.read(lenderProfileProvider.notifier).loadProfile(silent: true);

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(lenderProfileProvider);
    return MobileScaffold(
      title: 'Profile',
      accentColor: _accent,
      navItems: _navItems,
      body: profileState.isLoading && profileState.user == null
          ? const _ProfileSkeleton()
          : profileState.user == null
              ? _buildError(profileState.error)
              : MobileRefresh(
                  color: _accent,
                  onRefresh: _refresh,
                  child: _buildProfile(profileState.user!),
                ),
    );
  }

  /// Text lang na pindot-pindot — bubukas ang popup ng section para makita
  /// at ma-edit ang existing details (walang card, walang arrow).
  Widget _buildSectionLink(String title, IconData icon, VoidCallback onTap) {
    return ModernInfoCard(
      title: title,
      icon: icon,
      rows: const [],
      flat: true,
      // May icon ang bawat link — hindi plain text lang na mahirap i-scan.
      showIcon: true,
      onTap: onTap,
    );
  }

  Widget _buildError(String? message) {
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
                color: ModernProfileStyles.iconBg,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.person_off_outlined,
                  size: 24, color: ModernProfileStyles.iconColor),
            ),
            const SizedBox(height: 12),
            Text(message ?? 'Unable to load profile',
                textAlign: TextAlign.center, style: ModernProfileStyles.sub),
            const SizedBox(height: 16),
            ModernPrimaryButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              color: _accent,
              onPressed: () =>
                  ref.read(lenderProfileProvider.notifier).loadProfile(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(dynamic user) {
    final userModel = ref.watch(lenderProfileProvider).user;
    final phone = user.phoneNumber as String? ?? '';
    final accountStatus = user.accountStatus as String?;
    final fullName = _buildFullName(userModel ?? user);
    final accountUpgradeStatus =
        (userModel?.accountUpgradeStatus ?? 'not_submitted').toLowerCase();
    final isVerified = accountUpgradeStatus == 'verified';
    final status = _statusStyle(accountStatus);
    // Desktop: dalawang column — kaliwang rail ang identity + account actions,
    // kanang column ang mga section. Mobile: isang column pa rin.
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    // ── Identity (header + verification) — ISANG pinagmumulan lang ito, at ang
    // pagkaka-ayos lang ang pinag-iba ng mobile at desktop. ──
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModernProfileHeader(
          name: fullName,
          subtitles: [phone],
          photoUrl: user.profilePhotoUrl as String?,
          accent: _accent,
          onAvatarUploaded: _updateAvatar,
          statusLabel: status.label,
          statusColor: status.fg,
          statusBg: status.bg,
          statusAsText: true,
          // Lender profile: photo sits directly on the page background —
          // no card / ring "plate" behind the profile picture.
          flat: true,
        ),
        const SizedBox(height: 16),
        // Kapag verified na, may sariling "Edit" button ang bawat section sa
        // ibaba (Personal Details / Residence Address) — hindi na kailangan
        // ang isang "Edit Profile" button na pinagsama ang lahat.
        if (userModel?.isWalkIn == true) ...[
          const SizedBox(height: 12),
          _buildWalkInNote(userModel?.inOfficeApplication,
              isVerified: isVerified),
        ],
      ],
    );

    // ── Mga section ng profile (sa desktop, ito ang kanang column) ──
    final sections = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Walang card box (inutos ng user) — plain na link lang, at deretso
        // ito sa "Upgrade Account" form (hindi sa status page). Nasa TAAS ito
        // ng Notifications section (inutos ng user).
        if (!isVerified) ...[
          _buildSectionLink(
            'Complete Verification',
            Icons.verified_outlined,
            () => context.push(RouteConstants.lenderAccountUpgrade),
          ),
          const SizedBox(height: 12),
        ],
        if (isVerified) ...[
          const SizedBox(height: 20),
          const ModernSectionLabel('Personal'),
          // Text lang na pindot-pindot ang titles — bubukas ang popup na may
          // existing details at pwedeng i-edit doon (kapareho ng rider).
          _buildSectionLink('Personal Details', Icons.person_outline_rounded,
              () => showLenderPersonalDetailsDialog(context)),
          const SizedBox(height: 12),
          _buildSectionLink('Email', Icons.email_outlined,
              () => showLenderEmailDialog(context)),
          const SizedBox(height: 12),
          _buildSectionLink('Residence Address', Icons.location_on_outlined,
              () => showLenderAddressDialog(context)),
          // 00128: Financial Details + Emergency Contact no longer live on the
          // lender profile — they are declared per loan inside the Apply Loan
          // flow and stored on the loan record.
        ],
        const SizedBox(height: 20),
        const ModernSectionLabel('Notifications'),
        // Push notifications ON/OFF — kapag OFF, ide-delete ang device token
        // kaya hindi na makakatanggap ng push ang device na ito (ang in-app
        // notification center ay hindi apektado).
        Consumer(builder: (context, ref, _) {
          final settings = ref.watch(appSettingsProvider);
          final notifier = ref.read(appSettingsProvider.notifier);
          return ModernMenuCard(flat: true, showIcon: true, items: [
            ModernMenuItem(
              icon: Icons.notifications_active_outlined,
              title: 'Push Notifications',
              onTap: () => notifier
                  .setPushNotifications(!settings.pushNotificationsEnabled),
              trailing: Switch.adaptive(
                value: settings.pushNotificationsEnabled,
                activeTrackColor: _accent,
                onChanged: (v) => notifier.setPushNotifications(v),
              ),
            ),
          ]);
        }),
        const SizedBox(height: 20),
        // MPIN — 4-digit na pang-kumpirmasyon sa lahat ng submission kapag
        // walang password o biometrics ang phone.
        const ModernSectionLabel('Security'),
        const MpinSettingsCard(flat: true, showIcon: true),
        const SizedBox(height: 12),
        // Google Authenticator (TOTP) — second factor sa login. Ang status,
        // enrollment (QR + manual key) at disable ay dito; ang pagsusuri ng
        // code ay Supabase Auth (`mfa.challenge` / `mfa.verify`).
        const MfaSettingsCard(flat: true, showIcon: true),
        const SizedBox(height: 20),
        const ModernSectionLabel('General'),
        ModernMenuCard(flat: true, showIcon: true, items: [
          ModernMenuItem(
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            onTap: () => _showSheet(
              title: 'Terms & Conditions',
              icon: Icons.description_outlined,
              sections: const [
                ModernSheetSection(
                    title: 'Introduction',
                    body:
                        'By accessing and using the Jireta Loans & Credit Corp. Web and Mobile-Based Digitized Lending Management System, I acknowledge and agree to the following terms and conditions:'),
                ModernSheetSection(
                    title: '1. Account Security',
                    body:
                        'I agree to provide accurate information during registration and to keep my account credentials and verification codes confidential. I understand that I am responsible for activities performed through my account.'),
                ModernSheetSection(
                    title: '2. Personal Information',
                    body:
                        'I authorize the company to collect, store, and process my personal information as necessary for account management, loan processing, payment monitoring, and other legitimate lending-related purposes, subject to applicable data privacy laws and the company\'s Privacy Policy.'),
                ModernSheetSection(
                    title: '3. Accurate Information',
                    body:
                        'I confirm that the personal and other information I provide through the system is true, accurate, and complete to the best of my knowledge.'),
                ModernSheetSection(
                    title: '4. Proper Use of the System',
                    body:
                        'I agree to use the system only for its intended purposes, including viewing loan information, monitoring payment schedules, receiving notifications, and accessing authorized lending services.'),
                ModernSheetSection(
                    title: '5. Notifications and Updates',
                    body:
                        'I understand that the company may send relevant notifications regarding my account, loan application, payment schedule, payment status, and other important lending-related updates.'),
                ModernSheetSection(
                    title: '6. Acknowledgment of Terms',
                    body:
                        'I understand that accepting these Terms and Conditions allows me to proceed with system access. However, accepting these terms does not automatically constitute loan approval or a loan agreement.'),
                ModernSheetSection(
                    title: '7. Agreement and Acceptance',
                    body:
                        'By checking the acceptance box, I confirm that I have read, understood, and agreed to these Terms and Conditions.'),
                ModernSheetSection(
                    title: 'Jireta Loans & Credit Corp.',
                    body: 'Sta. Barbara, Pangasinan'),
              ],
            ),
          ),
          ModernMenuItem(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () => _showSheet(
              title: 'Privacy Policy',
              icon: Icons.privacy_tip_outlined,
              // Buong Privacy Policy mula sa IISANG pinagmumulan
              // ([kPrivacyPolicySections]) — kapareho ng nasa footer ng web
              // login at ng mga legal sheet sa ibang screens.
              sections: [
                for (final s in kPrivacyPolicySections)
                  ModernSheetSection(title: s.title, body: s.body),
              ],
            ),
          ),
          ModernMenuItem(
            icon: Icons.support_agent_outlined,
            title: 'Help Center',
            onTap: () => _showSheet(
              title: 'Help Center',
              icon: Icons.support_agent_outlined,
              // Kaparehong FAQ (dropdown/collapsible ang sagot) ng Help Center
              // sa mobile login screen.
              collapsible: true,
              // Mga channel ng suporta: Chat (hindi pa available), email, at
              // numero — pantay ang icon at text alignment ng tatlo.
              footer: _supportContactInfo(context),
              sections: const [
                ModernSheetSection(
                    title: 'How do I log in to the app?',
                    body:
                        'Enter your registered mobile number and tap Send OTP. You will receive a one-time password (OTP) on your Gmail and via SMS to verify your account.'),
                ModernSheetSection(
                    title: 'What if I do not receive my OTP?',
                    body:
                        'Wait at least 60 seconds before tapping Resend OTP. Check your Gmail inbox (including Spam) and SMS. Make sure your mobile number and Gmail on file are correct and you have a stable connection.'),
                ModernSheetSection(
                    title: 'How do I apply for a loan?',
                    body:
                        'After logging in, go to the Loans section and tap Apply. Fill out the required details and submit your application for review.'),
                ModernSheetSection(
                    title: 'What are the loan requirements?',
                    body:
                        'You need a valid government-issued ID, business permit, and face recognition verification. All documents are subject to verification.'),
                ModernSheetSection(
                    title: 'How do I pay for my loan?',
                    body:
                        'Payments can be made through GCash, office cash payment, or rider cash collection. A receipt is issued for every payment.'),
                ModernSheetSection(
                    title: 'Is my personal data safe?',
                    body:
                        'Yes. We protect your personal information in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173).'),
                ModernSheetSection(
                    title: 'Who can I contact for support?',
                    body:
                        'Visit our office during business hours or reach out to our authorized personnel. Never share your OTP or account credentials with anyone.'),
              ],
            ),
          ),
        ]),
      ],
    );

    // ── Account actions (bersyon + logout) ──
    const versionLabel = Center(
      child: Text(
        'Version ${AppConfig.appVersion}',
        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
      ),
    );
    // Sa desktop, may "Log Out" na sa sidebar, kaya bersyon lang ang nasa
    // ibaba ng profile. Sa mobile, dito pa rin ang logout button.
    const desktopFooter = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 16),
        versionLabel,
      ],
    );
    final footer = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        versionLabel,
        const SizedBox(height: 8),
        _buildLogoutButton(),
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
                    children: [
                      identity,
                      desktopFooter,
                    ],
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
        children: [
          identity,
          sections,
          footer,
        ],
      ),
    );
  }

  void _showSheet({
    required String title,
    required IconData icon,
    required List<ModernSheetSection> sections,
    bool collapsible = false,
    Widget? footer,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ModernInfoSheet(
        title: title,
        icon: icon,
        sections: sections,
        collapsible: collapsible,
        footer: footer,
      ),
    );
  }

  /// Mga channel ng suporta sa dulo ng Help Center FAQ — Chat, email, at
  /// numero. Iisa ang icon at text alignment ng tatlo para pantay ang hanay.
  /// Kapag pinindot ang email/numero, direktang bubukas ang mail app
  /// (`mailto:`) o dialer (`tel:`) ng device.
  Widget _supportContactInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SupportContactLine(
          icon: Icons.chat_bubble_outline_rounded,
          text: 'Chat',
          muted: true,
          badge: 'Coming soon',
        ),
        const SizedBox(height: 2),
        _SupportContactLine(
          icon: Icons.mail_outline_rounded,
          text: AppConstants.supportEmail,
          onTap: () => _openContactApp(
            context,
            Uri(scheme: 'mailto', path: AppConstants.supportEmail),
          ),
        ),
        const SizedBox(height: 2),
        _SupportContactLine(
          icon: Icons.phone_outlined,
          text: AppConstants.supportPhone,
          onTap: () => _openContactApp(
            context,
            Uri(scheme: 'tel', path: AppConstants.supportPhone),
          ),
        ),
      ],
    );
  }

  /// Bubukas ng default na app ng device: mail app para sa email, dialer para
  /// sa numero. May snackbar kapag walang app na kayang humawak sa link.
  Future<void> _openContactApp(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) return;
    } catch (_) {
      // Dadausan ng snackbar sa ibaba — walang crash kapag walang mail/dialer
      // app sa device (hal. desktop browser na walang naka-set na handler).
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open ${uri.scheme}: app on this device.'),
      ),
    );
  }

  _StatusStyle _statusStyle(String? status) {
    final s = (status ?? 'active').toLowerCase();
    return switch (s) {
      'active' =>
        const _StatusStyle('Active', AppColors.success, AppColors.successLight),
      'whitelisted' => const _StatusStyle(
          'Whitelisted', AppColors.success, AppColors.successLight),
      'suspended' => const _StatusStyle(
          'Suspended', AppColors.warning, AppColors.warningLight),
      'blacklisted' || 'deactivated' => _StatusStyle(
          s[0].toUpperCase() + s.substring(1),
          AppColors.error,
          AppColors.errorLight),
      _ => _StatusStyle(status ?? 'Active', AppColors.textSecondary,
          ModernProfileStyles.iconBg),
    };
  }

  String _buildFullName(dynamic user) {
    final parts = [
      user?.firstName,
      user?.middleName,
      user?.lastName,
      user?.suffix,
    ].where((e) => e != null && e.toString().isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  Widget _buildWalkInNote(Map<String, dynamic>? app,
      {bool isVerified = false}) {
    String dateLabel = '';
    final createdAt = app?['created_at']?.toString();
    if (createdAt != null) {
      final d = parseManila(createdAt);
      if (d != null) {
        dateLabel =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
    }
    final status = (app?['status']?.toString() ?? 'submitted').toLowerCase();
    // A walk-in account is auto-verified by staff at the office, so once the
    // upgrade is verified the "pending upgrade" copy is wrong — show verified.
    final detail = status == 'converted'
        ? 'Converted — loan created'
        : (isVerified
            ? 'Account verified — you can now apply for a loan'
            : 'Pending upgrade — complete verification to apply for a loan');
    return Container(
      width: double.infinity,
      decoration: ModernProfileStyles.card,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: ModernProfileStyles.iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.storefront_outlined,
                size: 17, color: ModernProfileStyles.iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Walk-in account',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  dateLabel.isEmpty ? detail : '$detail · $dateLabel',
                  style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAvatar(String url) async {
    await ref
        .read(lenderProfileProvider.notifier)
        .updateProfile({'profile_photo_url': url});
  }

  Widget _buildLogoutButton() {
    final isLoggingOut =
        ref.watch(authStateProvider.select((s) => s.isLoggingOut));
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: isLoggingOut ? null : _confirmLogout,
        icon: isLoggingOut
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
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
          side: const BorderSide(color: Color(0xFFF0CFCF)),
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    if (ref.read(authStateProvider).isLoggingOut) return;
    // (1) Confirm muna: "Are you sure to logout?" (Yes / No). Kapareho ng
    // web logout flow — hindi na tuloy agad ang logout sa isang tap.
    final confirmed = await showConfirmationDialog(
      context,
      // Walang heading — tanong lang at Yes/No na nasa gitna.
      title: '',
      message: 'Are you sure to logout?',
      confirmLabel: 'Yes',
      cancelLabel: 'No',
      isDangerous: true,
      centerText: true,
      // Walang icon at walang divider — simpleng tanong lang, at compact na
      // lapad (280) para hindi umabot sa buong screen sa phone.
      showIcon: false,
      showDivider: false,
      width: 280,
    );
    if (confirmed != true) return;
    if (!mounted || !context.mounted) return;
    // (2) Flow: button loading → logout → success modal steady for 2s → login
    // page. The redirect is held while the modal is up so it can't yank the
    // stack mid-modal. The button's "Logging out…" spinner shows the moment
    // it's tapped (setLoggingOut is flipped at the start of authProvider.logout).
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
}

class _StatusStyle {
  final String label;
  final Color fg;
  final Color bg;
  const _StatusStyle(this.label, this.fg, this.bg);
}

/// Skeletal loading na kamukha ng profile layout: header, button,
/// info cards, menu card, at logout button.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Shimmer.fromColors(
        baseColor: AppColors.shimmerBase,
        highlightColor: AppColors.shimmerHighlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar + name + phone + status pill
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 150,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 100,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 70,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Primary button
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 20),
            // Section label + info card (5 rows)
            Container(
              width: 80,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 10),
            const _SkeletonCard(rows: 5),
            const SizedBox(height: 12),
            // Second info card (3 rows)
            const _SkeletonCard(rows: 3),
            const SizedBox(height: 20),
            // Menu card (4 rows)
            Container(
              width: 80,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 10),
            const _SkeletonCard(rows: 4),
            const SizedBox(height: 16),
            // Logout button
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final int rows;
  const _SkeletonCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: List.generate(
          rows,
          (i) => Padding(
            padding: EdgeInsets.only(bottom: i == rows - 1 ? 0 : 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 120,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Isang linya ng contact channel (icon + text) sa Help Center. Pare-pareho
/// ang sukat ng icon at gap ng lahat ng linya, kaya pantay-pantay ang icon
/// column at text column mula Chat hanggang email at numero.
class _SupportContactLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  /// Gray ang icon/text para sa channel na hindi pa available (Chat).
  final bool muted;

  /// Maliit na label sa dulo ng linya (hal. "Coming soon").
  final String? badge;

  const _SupportContactLine({
    required this.icon,
    required this.text,
    this.onTap,
    this.muted = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppColors.textTertiary : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: color,
                  fontWeight: muted ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9EBF0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
