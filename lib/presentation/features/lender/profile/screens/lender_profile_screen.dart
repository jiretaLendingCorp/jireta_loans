// lib/presentation/features/lender/profile/screens/lender_profile_screen.dart
// Modern Minimalist redesign: neutral cards, hairline dividers,
// quiet icons, single accent (lender navy). No serif, no heavy shadows.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/config/app_config.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/extensions/string_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/profile/modern_profile_widgets.dart';
import '../../../../shared/providers/auth_state_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../providers/lender_profile_provider.dart';

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
      label: 'History',
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

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(lenderProfileProvider);
    return MobileScaffold(
      title: 'Profile',
      accentColor: _accent,
      navItems: _navItems,
      body: profileState.isLoading && profileState.user == null
          ? const Center(
              child: CircularProgressIndicator(color: _accent))
          : profileState.user == null
              ? _buildError(profileState.error)
              : _buildProfile(profileState.user!),
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
                textAlign: TextAlign.center,
                style: ModernProfileStyles.sub),
            const SizedBox(height: 16),
            ModernPrimaryButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              color: _accent,
              onPressed: () => ref
                  .read(lenderProfileProvider.notifier)
                  .loadProfile(),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          ),
          if (userModel?.isWalkIn == true) ...[
            const SizedBox(height: 12),
            _buildWalkInNote(userModel?.inOfficeApplication),
          ],
          const SizedBox(height: 16),
          if (isVerified)
            ModernPrimaryButton(
              label: 'Edit Profile',
              icon: Icons.edit_outlined,
              color: _accent,
              onPressed: () =>
                  context.push('${RouteConstants.lenderProfile}/edit'),
            )
          else
            ModernMenuCard(items: [
              ModernMenuItem(
                icon: Icons.verified_outlined,
                title: 'Complete Verification',
                subtitle: 'Unlock loan applications',
                onTap: () => context
                    .push(RouteConstants.lenderAccountUpgradeStatus),
              ),
            ]),
          if (isVerified) ...[
            const SizedBox(height: 20),
            const ModernSectionLabel('Personal'),
            ModernInfoCard(
              title: 'Personal Details',
              icon: Icons.person_outline_rounded,
              rows: [
                ModernInfoRowData(
                    icon: Icons.person_outline_rounded,
                    label: 'Full name',
                    value: fullName),
                ModernInfoRowData(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: phone.maskPhone()),
                ModernInfoRowData(
                    icon: Icons.wc_outlined,
                    label: 'Gender',
                    value: _formatLabel(user.gender)),
                ModernInfoRowData(
                    icon: Icons.favorite_border_rounded,
                    label: 'Civil status',
                    value: _formatLabel(user.civilStatus)),
                ModernInfoRowData(
                  icon: Icons.cake_outlined,
                  label: 'Date of birth',
                  value: userModel?.dateOfBirth != null
                      ? _formatDate(userModel!.dateOfBirth!)
                      : '—',
                ),
                ModernInfoRowData(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: _buildAddress(userModel)),
              ],
            ),
            const SizedBox(height: 12),
            ModernInfoCard(
              title: 'Financial Details',
              icon: Icons.account_balance_wallet_outlined,
              rows: [
                ModernInfoRowData(
                    icon: Icons.work_outline_rounded,
                    label: 'Employment',
                    value: _formatLabel(user.employmentType)),
                ModernInfoRowData(
                    icon: Icons.business_outlined,
                    label: 'Employer',
                    value: user.employerName?.toString() ?? '—'),
                ModernInfoRowData(
                  icon: Icons.payments_outlined,
                  label: 'Monthly income',
                  value: user.monthlyIncome != null
                      ? (user.monthlyIncome as num).toDouble().toCurrency
                      : '—',
                ),
                ModernInfoRowData(
                    icon: Icons.savings_outlined,
                    label: 'Source of funds',
                    value: _formatLabel(user.sourceOfFunds)),
              ],
            ),
            const SizedBox(height: 12),
            ModernInfoCard(
              title: 'Emergency Contact',
              icon: Icons.emergency_outlined,
              rows: _buildEmergencyRows(userModel?.emergencyContacts),
            ),
          ],
          const SizedBox(height: 20),
          const ModernSectionLabel('General'),
          ModernMenuCard(items: [
            ModernMenuItem(
              icon: Icons.description_outlined,
              title: 'Terms & Conditions',
              subtitle: 'Loan terms and policies',
              onTap: () => _showSheet(
                title: 'Terms & Conditions',
                icon: Icons.description_outlined,
                sections: const [
                  ModernSheetSection(
                      title: 'Agreement to Terms',
                      body:
                          'By accessing and using the Jireta Loans & Credit Corp 1966 mobile application, you agree to be bound by these Terms and Conditions and our Privacy Policy.'),
                  ModernSheetSection(
                      title: 'Loan Services',
                      body:
                          'Jireta Loans & Credit Corp 1966 offers loans from ₱3,000 to ₱500,000 at 20% interest per term, subject to verification and credit evaluation.'),
                  ModernSheetSection(
                      title: 'Interest & Penalties',
                      body:
                          'All loans carry 20% interest. A 20% penalty on the total payable applies after one (1) month of delay.'),
                  ModernSheetSection(
                      title: 'Account Requirements',
                      body:
                          'Submit a valid government ID, proof of billing, selfie verification, and proof of income. All documents are subject to verification.'),
                  ModernSheetSection(
                      title: 'Data Privacy',
                      body:
                          'We process your information under the Data Privacy Act of 2012 (RA 10173), solely for loan processing and account management.'),
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
                      title: 'Data We Collect',
                      body:
                          'We collect your name, contact details, government IDs, financial information, and location data for investigation and collection.'),
                  ModernSheetSection(
                      title: 'How We Use Your Data',
                      body:
                          'Your data is stored securely and used only for loan processing, identity verification, and regulatory compliance.'),
                  ModernSheetSection(
                      title: 'Your Rights',
                      body:
                          'You may access, correct, and request deletion of your data under the Data Privacy Act of 2012 (RA 10173).'),
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
                      title: 'How do I apply for a loan?',
                      body:
                          'Go to Loans and tap Apply. Fill out the required details and submit your application for review.'),
                  ModernSheetSection(
                      title: 'How do I pay?',
                      body:
                          'Pay via GCash (Xendit), office cash payment, or rider cash collection. A receipt is issued for every payment.'),
                  ModernSheetSection(
                      title: 'Is my data safe?',
                      body:
                          'Yes. We protect your information under the Data Privacy Act of 2012 (RA 10173). Never share your OTP with anyone.'),
                ],
              ),
            ),
            ModernMenuItem(
              icon: Icons.info_outline_rounded,
              title: 'About Jireta',
              subtitle: 'Since 1966',
              onTap: () => _showSheet(
                title: 'About Jireta',
                icon: Icons.info_outline_rounded,
                sections: const [
                  ModernSheetSection(
                      title: 'Company',
                      body:
                          'Jireta Loans & Credit Corp 1966 provides accessible financial assistance to Filipinos.'),
                  ModernSheetSection(
                      title: 'Our Services',
                      body:
                          'Loans from ₱3,000 to ₱500,000 with clear terms and transparent rates.'),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _buildLogoutButton(),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Version ${AppConfig.appVersion}',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textTertiary),
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

  _StatusStyle _statusStyle(String? status) {
    final s = (status ?? 'active').toLowerCase();
    return switch (s) {
      'active' => const _StatusStyle('Active', AppColors.success,
          AppColors.successLight),
      'whitelisted' => const _StatusStyle('Whitelisted', AppColors.success,
          AppColors.successLight),
      'suspended' => const _StatusStyle('Suspended', AppColors.warning,
          AppColors.warningLight),
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

  List<ModernInfoRowData> _buildEmergencyRows(
      List<Map<String, dynamic>>? contacts) {
    if (contacts == null || contacts.isEmpty) {
      return const [
        ModernInfoRowData(
            icon: Icons.emergency_outlined,
            label: 'Emergency contact',
            value: '—')
      ];
    }
    final c = contacts.first;
    return [
      ModernInfoRowData(
          icon: Icons.person_outline_rounded,
          label: 'Name',
          value: c['name']?.toString() ?? '—'),
      ModernInfoRowData(
          icon: Icons.family_restroom_outlined,
          label: 'Relationship',
          value: c['relationship']?.toString() ?? '—'),
      ModernInfoRowData(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value:
              (c['phone_number']?.toString() ?? '').maskPhone()),
      if (c['address'] != null && c['address'].toString().isNotEmpty)
        ModernInfoRowData(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: c['address'].toString()),
    ];
  }

  String _buildAddress(dynamic user) {
    final parts = [
      user?.streetAddress,
      user?.barangay,
      user?.city,
      user?.province,
      user?.zipCode,
    ].where((e) => e != null && e.toString().isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatLabel(dynamic value) {
    if (value == null || value.toString().isEmpty) return '—';
    final s = value.toString();
    return s
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  Widget _buildWalkInNote(Map<String, dynamic>? app) {
    String dateLabel = '';
    final createdAt = app?['created_at']?.toString();
    if (createdAt != null) {
      final d = DateTime.tryParse(createdAt);
      if (d != null) {
        dateLabel =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
    }
    final status = (app?['status']?.toString() ?? 'submitted').toLowerCase();
    final detail = status == 'converted'
        ? 'Converted — loan created'
        : 'Pending upgrade — complete verification to apply for a loan';
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    if (ref.read(authStateProvider).isLoggingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Log out?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('You will need to log in again to continue.',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authProvider.notifier).logout();
    if (mounted && context.mounted) {
      context.go(RouteConstants.mobileLogin);
    }
  }
}

class _StatusStyle {
  final String label;
  final Color fg;
  final Color bg;
  const _StatusStyle(this.label, this.fg, this.bg);
}
