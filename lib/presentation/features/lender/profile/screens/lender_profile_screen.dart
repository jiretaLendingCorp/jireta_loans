// lib/presentation/features/lender/profile/screens/lender_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/config/app_config.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/extensions/string_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/profile_avatar_upload.dart';
import '../../../../shared/providers/auth_state_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../providers/lender_profile_provider.dart';
import 'widgets/legal_info_sheet.dart';

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

  int _expandedSection = -1;

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
      title: 'My Profile',
      accentColor: AppColors.lenderBlue,
      navItems: _navItems,
      body: profileState.isLoading && profileState.user == null
          ? const Center(child: CircularProgressIndicator())
          : profileState.user == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(profileState.error ?? 'Unable to load profile',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.lenderBlue),
                              onPressed: () => ref.read(lenderProfileProvider.notifier).loadProfile(),
                              icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                              label: const Text('Retry', style: TextStyle(color: Colors.white)),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await ref.read(authProvider.notifier).logout();
                                if (context.mounted) context.go(RouteConstants.mobileLogin);
                              },
                              icon: const Icon(Icons.logout, size: 18),
                              label: const Text('Re-login'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : _buildProfile(profileState.user!),
    );
  }

  Widget _buildProfile(dynamic user) {
    final userModel = ref.watch(lenderProfileProvider).user;
    final phone = user.phoneNumber as String? ?? '';
    final firstName = user.firstName as String? ?? '';
    final accountStatus = user.accountStatus as String?;
    final fullName = _buildFullName(userModel ?? user);
    final accountUpgradeStatus =
        (userModel?.accountUpgradeStatus ?? 'not_submitted').toLowerCase();
    final isVerified = accountUpgradeStatus == 'verified';

    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minHeight: constraints.maxHeight - 16),
          child: IntrinsicHeight(
            child: Column(children: [
              _buildHeader(fullName, firstName, phone,
                  user.profilePhotoUrl as String?, accountStatus),
              if (isVerified) ...[
                const SizedBox(height: 16),
                _buildEditProfileButton(),
              ],
              const SizedBox(height: 22),
              _sectionTitle('Verification'),
              const SizedBox(height: 10),
              _buildAccountUpgradeCard(userModel?.accountUpgradeStatus),
              if (isVerified) ...[
                const SizedBox(height: 16),
                _CollapsibleSection(
                  icon: Icons.person_outline,
                  title: 'Personal Details',
                  isExpanded: _expandedSection == 0,
                  onToggle: () => setState(
                      () => _expandedSection = _expandedSection == 0 ? -1 : 0),
                  children: [
                    _infoRow(Icons.person, 'Full Name', fullName),
                    _infoRow(Icons.phone, 'Phone', phone.maskPhone()),
                    _infoRow(
                        Icons.wc, 'Gender', _formatLabel(user.gender)),
                    _infoRow(Icons.favorite_border, 'Civil Status',
                        _formatLabel(user.civilStatus)),
                    _infoRow(
                        Icons.cake_outlined,
                        'Date of Birth',
                        userModel?.dateOfBirth != null
                            ? _formatDate(userModel!.dateOfBirth!)
                            : '—'),
                    _infoRow(Icons.location_on_outlined, 'Address',
                        _buildAddress(userModel)),
                  ],
                ),
                const SizedBox(height: 12),
                _CollapsibleSection(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Financial Details',
                  isExpanded: _expandedSection == 1,
                  onToggle: () => setState(
                      () => _expandedSection = _expandedSection == 1 ? -1 : 1),
                  children: [
                    _infoRow(
                        Icons.account_balance_wallet,
                        'GCash',
                        user.gcashNumber != null
                            ? (user.gcashNumber as String).maskPhone()
                            : '—'),
                    _infoRow(Icons.work_outline, 'Employment',
                        _formatLabel(user.employmentType)),
                    _infoRow(Icons.business, 'Employer',
                        user.employerName?.toString() ?? '—'),
                    _infoRow(
                        Icons.payments,
                        'Monthly Income',
                        user.monthlyIncome != null
                            ? (user.monthlyIncome as num)
                                .toDouble()
                                .toCurrency
                            : '—'),
                    _infoRow(Icons.savings_outlined, 'Source of Funds',
                        _formatLabel(user.sourceOfFunds)),
                  ],
                ),
                const SizedBox(height: 12),
                _CollapsibleSection(
                  icon: Icons.emergency_outlined,
                  title: 'Emergency Contact',
                  isExpanded: _expandedSection == 2,
                  onToggle: () => setState(
                      () => _expandedSection = _expandedSection == 2 ? -1 : 2),
                  children: _buildEmergencyRows(userModel?.emergencyContacts),
                ),
              ],
              const SizedBox(height: 22),
              _sectionTitle('Legal'),
              const SizedBox(height: 10),
              _buildLegalCard(context),
              const SizedBox(height: 22),
              _sectionTitle('Support'),
              const SizedBox(height: 10),
              _buildSupportCard(context),
              const Spacer(),
              const SizedBox(height: 22),
              const Text(
                'Version ${AppConfig.appVersion}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 12),
              _buildLogoutButton(),
            ]),
          ),
        ),
      );
    });
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

  List<Widget> _buildEmergencyRows(List<Map<String, dynamic>>? contacts) {
    if (contacts == null || contacts.isEmpty) {
      return [_infoRow(Icons.emergency_outlined, 'Emergency Contact', '—')];
    }
    final c = contacts.first;
    return [
      _infoRow(Icons.person_outline, 'Name', c['name']?.toString() ?? '—'),
      _infoRow(Icons.family_restroom, 'Relationship',
          c['relationship']?.toString() ?? '—'),
      _infoRow(Icons.phone, 'Phone',
          (c['phone_number']?.toString() ?? '').maskPhone()),
      if (c['address'] != null && c['address'].toString().isNotEmpty)
        _infoRow(
            Icons.location_on_outlined, 'Address', c['address'].toString()),
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

  Widget _buildHeader(String fullName, String firstName, String phone,
      String? photoUrl, String? accountStatus) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _statusPill(accountStatus),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.lenderBlue, width: 3),
          ),
          child: ProfileAvatarUpload(
            photoUrl: photoUrl,
            name: firstName,
            color: AppColors.lenderBlue,
            radius: 38,
            onUploaded: _updateAvatar,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.lenderBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          phone,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
        color: AppColors.lenderBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lenderBlue.withValues(alpha: 0.3)),
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
                color: AppColors.lenderBlue),
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

  Widget _buildAccountUpgradeCard(String? accountUpgradeStatus) {
    final status = (accountUpgradeStatus ?? 'not_submitted').toLowerCase();
    final (Color color, IconData icon, String label) = switch (status) {
      'verified' => (AppColors.success, Icons.verified_user, 'Verified'),
      'rejected' => (AppColors.error, Icons.cancel_outlined, 'Rejected'),
      'submitted' || 'under_review' => (
          AppColors.warning,
          Icons.pending_outlined,
          'Under Review'
        ),
      _ => (AppColors.textSecondary, Icons.badge_outlined, 'Not Submitted'),
    };
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
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        title: const Text('Account Upgrade Verification',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.deepNavy)),
        subtitle: Text('Status: $label',
            style: TextStyle(fontSize: 12, color: color)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ),
        onTap: () => context.push(RouteConstants.lenderAccountUpgradeStatus),
      ),
    );
  }

  Widget _buildLegalCard(BuildContext context) {
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
                color: AppColors.lenderBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.description_outlined,
                color: AppColors.lenderBlue, size: 22),
          ),
          title: const Text('Terms & Conditions',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy)),
          subtitle: const Text('Review the terms of the loan service',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const LegalInfoSheet(
              title: 'Terms & Conditions',
              sections: [
                LegalSection(
                  title: '1. Agreement to Terms',
                  body:
                      'By accessing and using the Jireta Loans & Credit Corp 1966 mobile application, you agree to be bound by these Terms and Conditions and our Privacy Policy.',
                ),
                LegalSection(
                  title: '2. Loan Services',
                  body:
                      'Jireta Loans & Credit Corp 1966 offers lending services ranging from \u20B13,000 to \u20B1500,000 with an interest rate of 20% per loan term. Loan amounts and terms are subject to credit evaluation, account upgrade verification, and credit investigation.',
                ),
                LegalSection(
                  title: '3. Interest & Penalties',
                  body:
                      'All loans carry a 20% interest rate on the principal amount. A penalty of 20% on the total payable amount will be applied if payment is delayed by one (1) month or more.',
                ),
                LegalSection(
                  title: '4. Account Upgrade Requirements',
                  body:
                      'You are required to submit valid government-issued identification, proof of billing, selfie verification, and proof of income. All documents are subject to verification by authorized personnel.',
                ),
                LegalSection(
                  title: '5. Credit Investigation',
                  body:
                      'Loan applications are subject to a credit investigation conducted by authorized riders. You agree to cooperate with and receive visits from assigned investigators.',
                ),
                LegalSection(
                  title: '6. Payment Methods',
                  body:
                      'Payments may be made through GCash (via Xendit payment gateway), office cash payment, or rider cash collection. All transactions are recorded and receipts are issued.',
                ),
                LegalSection(
                  title: '7. Data Privacy',
                  body:
                      'We collect and process your personal information in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173) and our Privacy Policy. Your information is used solely for loan processing and account management.',
                ),
                LegalSection(
                  title: '8. Prohibited Acts',
                  body:
                      'You agree not to provide false information, commit fraud, or use the application for any unlawful purpose. Violations may result in account suspension, blacklisting, and legal action.',
                ),
                LegalSection(
                  title: '9. Governing Law',
                  body:
                      'These terms are governed by the laws of the Republic of the Philippines. Any disputes shall be resolved in the appropriate courts of the Philippines.',
                ),
                LegalSection(
                  title: '10. Contact',
                  body:
                      'For inquiries, please visit our office or contact our authorized personnel. Do not share your OTP or account credentials with anyone.',
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: AppColors.lenderBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.privacy_tip_outlined,
                color: AppColors.lenderBlue, size: 22),
          ),
          title: const Text('Privacy Policy',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy)),
          subtitle: const Text('How we collect and protect your data',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const LegalInfoSheet(
              title: 'Privacy Policy',
              sections: [
                LegalSection(
                  title: 'Data We Collect',
                  body:
                      'We collect your personal information including name, contact details, government IDs, financial information, and location data (for credit investigation and cash collection).',
                ),
                LegalSection(
                  title: 'How We Use Your Data',
                  body:
                      'Your data is stored securely and used only for loan processing, identity verification, and regulatory compliance.',
                ),
                LegalSection(
                  title: 'Your Rights',
                  body:
                      'You have the right to access, correct, and request deletion of your data in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173).',
                ),
              ],
            ),
          ),
        ),
      ]),
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
                color: AppColors.lenderBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.support_agent,
                color: AppColors.lenderBlue, size: 22),
          ),
          title: const Text('Help Center',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy)),
          subtitle: const Text('Frequently asked questions and support',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const LegalInfoSheet(
              title: 'Help Center',
              sections: [
                LegalSection(
                  title: 'How do I log in to the app?',
                  body:
                      'Enter your registered mobile number and tap Send OTP. You will receive a one-time password (OTP) to verify your account.',
                ),
                LegalSection(
                  title: 'What if I do not receive my OTP?',
                  body:
                      'Wait at least 60 seconds before requesting a new OTP. Make sure your mobile number is correct and you have a stable connection.',
                ),
                LegalSection(
                  title: 'How do I apply for a loan?',
                  body:
                      'After logging in, go to the Loans section and tap Apply. Fill out the required details and submit your application for review.',
                ),
                LegalSection(
                  title: 'What are the loan requirements?',
                  body:
                      'You need a valid government-issued ID, proof of billing, selfie verification, and proof of income. All documents are subject to verification.',
                ),
                LegalSection(
                  title: 'How do I pay for my loan?',
                  body:
                      'Payments can be made through GCash (via Xendit), office cash payment, or rider cash collection. A receipt is issued for every payment.',
                ),
                LegalSection(
                  title: 'Is my personal data safe?',
                  body:
                      'Yes. We protect your personal information in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173).',
                ),
                LegalSection(
                  title: 'Who can I contact for support?',
                  body:
                      'Visit our office during business hours or reach out to our authorized personnel. Never share your OTP or account credentials with anyone.',
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: AppColors.lenderBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.info_outline,
                color: AppColors.lenderBlue, size: 22),
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
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const LegalInfoSheet(
              title: 'About Jireta',
              sections: [
                LegalSection(
                  title: 'Company',
                  body:
                      'Jireta Loans & Credit Corp 1966 is a lending company offering financial assistance to Filipinos.',
                ),
                LegalSection(
                  title: 'Our Services',
                  body:
                      'We provide loans ranging from \u20B13,000 to \u20B1500,000 with clear terms and transparent interest rates.',
                ),
                LegalSection(
                  title: 'Our History',
                  body:
                      'Founded in 1966, we have served our clients for decades with reliable and accessible lending services.',
                ),
                LegalSection(
                  title: 'Our Commitment',
                  body:
                      'We are committed to providing fast, secure, and convenient loan processing through the mobile app.',
                ),
              ],
            ),
          ),
        ),
      ]),
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
            color: AppColors.lenderBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 17, color: AppColors.lenderBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
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

  Widget _buildEditProfileButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.lenderBlue,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit Profile',
            style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () => context.push('${RouteConstants.lenderProfile}/edit'),
      ),
    );
  }

  Widget _buildLogoutButton() {
    final isLoggingOut =
        ref.watch(authStateProvider.select((s) => s.isLoggingOut));
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: isLoggingOut
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.error),
              )
            : const Icon(Icons.logout),
        label: Text(isLoggingOut ? 'Logging out...' : 'Log Out',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        onPressed: isLoggingOut
            ? null
            : () async {
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
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Yes'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                // Global LogoutOverlay appears via authStateProvider.isLoggingOut
                await ref.read(authProvider.notifier).logout();
                if (mounted && context.mounted) {
                  context.go(RouteConstants.mobileLogin);
                }
              },
      ),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.lenderBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 17, color: AppColors.lenderBlue),
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
