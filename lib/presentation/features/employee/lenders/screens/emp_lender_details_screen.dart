// lib/presentation/features/employee/lenders/screens/emp_lender_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/details/details_actions_card.dart';
import '../../../../shared/widgets/details/details_section_card.dart';
import '../../../../shared/widgets/details/user_profile_header_card.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/providers/auth_state_provider.dart';
import '../widgets/emp_edit_lender_modal.dart';

final _lenderDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final ds = sl<UserRemoteDataSource>();
  return await ds.getProfileMap(userId: id);
});

class EmpLenderDetailsScreen extends ConsumerWidget {
  final String lenderId;
  const EmpLenderDetailsScreen({super.key, required this.lenderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_lenderDetailProvider(lenderId));
    final authState = ref.watch(authStateProvider);
    final canEdit = authState.role == 'head_manager';

    return WebScaffold(
      title: 'Lender Details',
      actions: [
        TextButton.icon(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
        ),
        const SizedBox(width: 8),
        if (canEdit) ...[
          OutlinedButton.icon(
            onPressed: () => state.whenData((data) => _showEdit(context, data)),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
          ),
          const SizedBox(width: 12),
        ],
      ],
      body: state.when(
        loading: () => _buildShimmer(),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (data) => _buildContent(context, ref, data),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) {
    final name =
        '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'.trim();
    final lp = data['lender_profiles'] as Map<String, dynamic>?;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserProfileHeaderCard(
            photoUrl: data['profile_photo_url'] as String?,
            name: name.isEmpty ? 'Lender' : name,
            subtitle: data['email'] ?? '—',
            subtitleIcon: Icons.email_outlined,
            roleLabel: 'Lender',
            roleIcon: Icons.account_balance_wallet_outlined,
            accentColor: AppColors.lenderBlue,
            accountStatus: data['account_status'] ?? 'active',
          ),
          const SizedBox(height: 20),
          DetailsSectionCard(
            title: 'Personal Information',
            icon: Icons.person_outline,
            accentColor: AppColors.lenderBlue,
            items: [
              DetailsItem('Gender', lp?['gender'] ?? '—'),
              DetailsItem('Civil Status', lp?['civil_status'] ?? '—'),
              DetailsItem(
                'Date of Birth',
                (lp?['date_of_birth'] ?? '').toString().length >= 10
                    ? (lp?['date_of_birth'] ?? '').toString().substring(0, 10)
                    : (lp?['date_of_birth'] ?? '—').toString(),
              ),
              DetailsItem('Employment', lp?['employment_type'] ?? '—'),
              DetailsItem('Employer', lp?['employer_name'] ?? '—'),
              DetailsItem(
                'Monthly Income',
                lp?['monthly_income'] != null
                    ? '₱${lp?['monthly_income']}'
                    : '—',
              ),
              DetailsItem('Source of Funds', lp?['source_of_funds'] ?? '—'),
            ],
          ),
          const SizedBox(height: 20),
          DetailsSectionCard(
            title: 'Contact Information',
            icon: Icons.phone_outlined,
            accentColor: AppColors.lenderBlue,
            items: [
              DetailsItem('Phone', data['phone_number'] ?? data['phone'] ?? '—'),
              DetailsItem('Email', data['email'] ?? '—'),
            ],
          ),
          const SizedBox(height: 20),
          DetailsSectionCard(
            title: 'Address',
            icon: Icons.location_on_outlined,
            accentColor: AppColors.lenderBlue,
            items: [
              DetailsItem('Street', data['street_address'] ?? '—'),
              DetailsItem('Barangay', data['barangay'] ?? '—'),
              DetailsItem('City', data['city'] ?? '—'),
              DetailsItem('Province', data['province'] ?? '—'),
              DetailsItem('Zip Code', data['zip_code'] ?? '—'),
            ],
          ),
          if ((data['emergency_contacts'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 20),
            DetailsSectionCard(
              title: 'Emergency Contact',
              icon: Icons.contact_emergency_outlined,
              accentColor: AppColors.lenderBlue,
              items: [
                for (final c in (data['emergency_contacts'] as List))
                  DetailsItem(
                    '${(c as Map)['name'] ?? '—'} (${c['relationship'] ?? '—'})',
                    '${c['phone_number'] ?? '—'}'
                    '${(c['address'] != null && c['address'].toString().isNotEmpty) ? ' — ${c['address']}' : ''}',
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          DetailsSectionCard(
            title: 'Account',
            icon: Icons.account_circle_outlined,
            accentColor: AppColors.lenderBlue,
            items: [
              DetailsItem('Account Status', data['account_status'] ?? '—'),
              DetailsItem(
                'Created At',
                (data['created_at'] ?? '').toString().length >= 10
                    ? (data['created_at'] ?? '').toString().substring(0, 10)
                    : (data['created_at'] ?? '—').toString(),
              ),
              DetailsItem(
                'Account Upgrade',
                '',
                valueWidget: StatusBadge(
                  status: lp?['account_upgrade_status'] ??
                      data['account_upgrade_status'] ??
                      'not_submitted',
                  small: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const DetailsActionsCard(
            title: 'Actions',
            icon: Icons.settings_outlined,
            accentColor: AppColors.lenderBlue,
            actions: [],
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() => ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, __) => const ShimmerLoader(height: 180),
      );

  void _showEdit(BuildContext context, Map<String, dynamic> data) {
    showDialog(
        context: context, builder: (_) => EmpEditLenderModal(lenderData: data));
  }
}
