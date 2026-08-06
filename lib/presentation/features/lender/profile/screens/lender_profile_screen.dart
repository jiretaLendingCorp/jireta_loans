// lib/presentation/features/lender/profile/screens/lender_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/extensions/string_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/profile_avatar_upload.dart';
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
        route: RouteConstants.lenderDashboard),
    MobileNavItem(
        icon: Icons.account_balance_outlined,
        activeIcon: Icons.account_balance,
        label: 'My Loan',
        route: RouteConstants.lenderLoans),
    MobileNavItem(
        icon: Icons.payment_outlined,
        activeIcon: Icons.payment,
        label: 'Payments',
        route: RouteConstants.lenderPayments),
    MobileNavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.lenderProfile),
  ];

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
      accentColor: AppColors.lenderPurple,
      navItems: _navItems,
      body: profileState.isLoading && profileState.user == null
          ? const Center(child: CircularProgressIndicator())
          : profileState.user == null
              ? Center(
                  child: Text(profileState.error ?? 'Unable to load profile',
                      style: const TextStyle(color: AppColors.textSecondary)),
                )
              : _buildProfile(profileState.user!),
    );
  }

  Widget _buildProfile(dynamic user) {
    final firstName = user.firstName as String? ?? '';
    final lastName = user.lastName as String? ?? '';
    final phone = user.phoneNumber as String? ?? '';
    final userModel = ref.watch(lenderProfileProvider).user;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildHeader(firstName, lastName, phone, user.profilePhotoUrl as String?),
        const SizedBox(height: 20),
        _buildInfoCard('Personal Details', [
          _infoRow(Icons.person, 'Full Name', '$firstName $lastName'),
          _infoRow(Icons.phone, 'Phone', phone.maskPhone()),
          _infoRow(Icons.wc, 'Gender', _formatLabel(user.gender)),
          _infoRow(Icons.favorite_border, 'Civil Status',
              _formatLabel(user.civilStatus)),
          _infoRow(Icons.cake_outlined, 'Date of Birth',
              userModel?.dateOfBirth != null
                  ? _formatDate(userModel!.dateOfBirth!)
                  : '—'),
          _infoRow(Icons.location_on_outlined, 'Address',
              _buildAddress(userModel)),
        ]),
        const SizedBox(height: 12),
        _buildInfoCard('Financial Details', [
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
                  ? (user.monthlyIncome as num).toDouble().toCurrency
                  : '—'),
          _infoRow(Icons.savings_outlined, 'Source of Funds',
              _formatLabel(user.sourceOfFunds)),
        ]),
        const SizedBox(height: 12),
        _buildKycCard(userModel?.kycStatus),
        const SizedBox(height: 12),
        _buildLegalCard(context),
        const SizedBox(height: 20),
        _buildActionButton(context),
      ]),
    );
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
    return s.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  Widget _buildHeader(String firstName, String lastName, String phone, String? photoUrl) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          ProfileAvatarUpload(
            photoUrl: photoUrl,
            name: firstName,
            color: AppColors.lenderPurple,
            radius: 40,
            onUploaded: _updateAvatar,
          ),
          const SizedBox(height: 12),
          Text('$firstName $lastName',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy)),
          Text(phone,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.lenderPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20)),
            child: const Text('Lender',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.lenderPurple)),
          ),
          const SizedBox(height: 8),
          const Text('Tap the camera icon to change your picture',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Future<void> _updateAvatar(String url) async {
    await ref
        .read(lenderProfileProvider.notifier)
        .updateProfile({'profile_photo_url': url});
  }

  Widget _buildKycCard(String? kycStatus) {
    final status = (kycStatus ?? 'pending').toLowerCase();
    final (Color color, IconData icon, String label) = switch (status) {
      'verified' => (AppColors.success, Icons.verified_user, 'Verified'),
      'rejected' => (AppColors.error, Icons.cancel_outlined, 'Rejected'),
      'submitted' || 'under_review' =>
        (AppColors.warning, Icons.pending_outlined, 'Under Review'),
      _ => (AppColors.textSecondary, Icons.badge_outlined, 'Not Submitted'),
    };
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 22),
        ),
        title: const Text('KYC Verification',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.deepNavy)),
        subtitle: Text('Status: $label',
            style: TextStyle(fontSize: 12, color: color)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: () => context.push(RouteConstants.lenderKycStatus),
      ),
    );
  }

  Widget _buildLegalCard(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: AppColors.lenderPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.description_outlined,
                color: AppColors.lenderPurple, size: 22),
          ),
          title: const Text('Terms & Conditions',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.deepNavy)),
          subtitle: const Text('Review the terms of the loan service',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
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
                      'Jireta Loans & Credit Corp 1966 offers lending services ranging from \u20B13,000 to \u20B1500,000 with an interest rate of 20% per loan term. Loan amounts and terms are subject to credit evaluation, KYC verification, and credit investigation.',
                ),
                LegalSection(
                  title: '3. Interest & Penalties',
                  body:
                      'All loans carry a 20% interest rate on the principal amount. A penalty of 20% on the total payable amount will be applied if payment is delayed by one (1) month or more.',
                ),
                LegalSection(
                  title: '4. KYC Requirements',
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
                color: AppColors.lenderPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.privacy_tip_outlined,
                color: AppColors.lenderPurple, size: 22),
          ),
          title: const Text('Privacy Policy',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.deepNavy)),
          subtitle: const Text('How we collect and protect your data',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
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

  Widget _buildInfoCard(String title, List<Widget> rows) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy)),
          const Divider(height: 20),
          ...rows,
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.lenderPurple),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary)),
        ])),
      ]),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    return Column(children: [
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.lenderPurple,
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
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.logout),
          label: const Text('Sign Out',
              style: TextStyle(fontWeight: FontWeight.w600)),
          onPressed: () async {
            await ref.read(authProvider.notifier).logout();
            if (mounted && context.mounted) {
              context.go(RouteConstants.mobileLogin);
            }
          },
        ),
      ),
    ]);
  }
}
