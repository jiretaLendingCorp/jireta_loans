// lib/presentation/features/lender/profile/screens/lender_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/extensions/string_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
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
        icon: Icons.notifications_outlined,
        activeIcon: Icons.notifications,
        label: 'Alerts',
        route: RouteConstants.lenderNotifications),
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
      body: profileState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : profileState.user == null
              ? Center(
                  child: Text(profileState.error ?? 'Unable to load profile',
                      style: const TextStyle(color: AppColors.textSecondary)),
                )
              : _buildProfile(profileState.user!.toJson()),
    );
  }

  Widget _buildProfile(Map<String, dynamic> user) {
    final lenderProfile = user['lender_profile'] as Map<String, dynamic>? ?? {};
    final firstName = user['first_name'] as String? ?? '';
    final lastName = user['last_name'] as String? ?? '';
    final phone = user['phone_number'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildHeader(firstName, lastName, phone),
        const SizedBox(height: 20),
        _buildInfoCard('Personal Details', [
          _infoRow(Icons.person, 'Full Name', '$firstName $lastName'),
          _infoRow(Icons.phone, 'Phone', phone.maskPhone()),
          _infoRow(Icons.wc, 'Gender', user['gender'] ?? '—'),
          _infoRow(Icons.favorite_border, 'Civil Status',
              lenderProfile['civil_status'] ?? '—'),
        ]),
        const SizedBox(height: 12),
        _buildInfoCard('Financial Details', [
          _infoRow(Icons.account_balance_wallet, 'GCash',
              lenderProfile['gcash_number']?.toString().maskPhone() ?? '—'),
          _infoRow(Icons.work_outline, 'Employment',
              lenderProfile['employment_type'] ?? '—'),
          _infoRow(Icons.business, 'Employer',
              lenderProfile['employer_name'] ?? '—'),
          _infoRow(
              Icons.payments,
              'Monthly Income',
              lenderProfile['monthly_income'] != null
                  ? (lenderProfile['monthly_income'] as num)
                      .toDouble()
                      .toCurrency
                  : '—'),
        ]),
        const SizedBox(height: 20),
        _buildActionButton(context),
      ]),
    );
  }

  Widget _buildHeader(String firstName, String lastName, String phone) {
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.lenderPurple,
              child: Text(initial,
                  style: const TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                      fontWeight: FontWeight.w700))),
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
        ]),
      ),
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
