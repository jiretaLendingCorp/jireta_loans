// lib/presentation/features/employee/lenders/screens/emp_lender_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
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

    return WebScaffold(
      title: 'Lender Details',
      actions: [
        OutlinedButton.icon(
          onPressed: () => state.whenData((data) => _showEdit(context, data)),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Edit'),
        ),
        const SizedBox(width: 12),
      ],
      body: state.when(
        loading: () => _buildShimmer(),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (data) => _buildContent(context, data),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPersonalInfo(data),
          const SizedBox(height: 20),
          _buildContactInfo(data),
          const SizedBox(height: 20),
          _buildAddressInfo(data),
          const SizedBox(height: 20),
          _buildEmergencyContact(data),
          if ((data['emergency_contacts'] as List?)?.isNotEmpty == true)
            const SizedBox(height: 20),
          _buildAccountStatus(data),
          const SizedBox(height: 20),
          _buildKycStatus(data),
        ],
      ),
    );
  }

  Widget _buildPersonalInfo(Map<String, dynamic> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.lenderPurple.withValues(alpha: 0.12),
                  child: Text(
                    ((data['first_name'] as String? ?? 'L')[0]).toUpperCase(),
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.lenderPurple),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'
                            .trim(),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(data['email'] ?? '—',
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                StatusBadge(status: data['account_status'] ?? 'active'),
              ],
            ),
            const Divider(height: 28),
            _buildSectionTitle('Personal Information'),
            const SizedBox(height: 12),
            _buildInfoGrid([
              _InfoItem('Gender', data['lender_profiles']?['gender'] ?? '—'),
              _InfoItem('Civil Status',
                  data['lender_profiles']?['civil_status'] ?? '—'),
              _InfoItem(
                  'Date of Birth', data['lender_profiles']?['date_of_birth'] ?? '—'),
              _InfoItem('Employment',
                  data['lender_profiles']?['employment_type'] ?? '—'),
              _InfoItem(
                  'Employer', data['lender_profiles']?['employer_name'] ?? '—'),
              _InfoItem(
                  'Monthly Income',
                  data['lender_profiles']?['monthly_income'] != null
                      ? '₱${data['lender_profiles']['monthly_income']}'
                      : '—'),
              _InfoItem('Source of Funds',
                  data['lender_profiles']?['source_of_funds'] ?? '—'),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressInfo(Map<String, dynamic> data) {
    final parts = [
      data['street_address'],
      data['barangay'],
      data['city'],
      data['province'],
      data['zip_code'],
    ].where((e) => e != null && e.toString().isNotEmpty).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Address'),
            const SizedBox(height: 12),
            Text(parts.isEmpty ? '—' : parts.join(', '),
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyContact(Map<String, dynamic> data) {
    final contacts = (data['emergency_contacts'] as List?) ?? [];
    if (contacts.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Emergency Contact'),
            const SizedBox(height: 12),
            _buildInfoGrid(contacts.map((c) {
              final m = c as Map<String, dynamic>;
              return _InfoItem('${m['name'] ?? '—'} (${m['relationship'] ?? '—'})',
                  '${m['phone_number'] ?? '—'}${(m['address'] != null && m['address'].toString().isNotEmpty) ? ' — ${m['address']}' : ''}');
            }).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildContactInfo(Map<String, dynamic> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Contact Information'),
            const SizedBox(height: 12),
            _buildInfoGrid([
              _InfoItem('Phone', data['phone'] ?? '—'),
              _InfoItem('GCash Number',
                  data['lender_profiles']?['gcash_number'] ?? '—'),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountStatus(Map<String, dynamic> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Account Status'),
            const SizedBox(height: 12),
            _buildInfoGrid([
              _InfoItem('Status', data['account_status'] ?? '—'),
              _InfoItem(
                  'Blacklisted',
                  (data['lender_profiles']?['is_blacklisted'] == true)
                      ? 'Yes'
                      : 'No'),
              _InfoItem('Created At',
                  (data['created_at'] ?? '').toString().substring(0, 10)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildKycStatus(Map<String, dynamic> data) {
    final kycStatus = data['lender_profiles']?['kyc_status'] ?? 'not_submitted';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('KYC Status'),
            const SizedBox(height: 12),
            Row(
              children: [
                StatusBadge(status: kycStatus),
                const SizedBox(width: 12),
                const Text('KYC verification status',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.deepNavy,
            letterSpacing: 0.5));
  }

  Widget _buildInfoGrid(List<_InfoItem> items) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: items
          .map((item) => SizedBox(
                width: 240,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(item.value,
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ))
          .toList(),
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

class _InfoItem {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);
}
