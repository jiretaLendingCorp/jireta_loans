// lib/presentation/features/employee/loans/screens/emp_loan_application_details_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../head_manager/disbursements/widgets/rider_disburse_assign_modal.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

final _empLoanDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return await sl<LoanRemoteDataSource>().getDetails(loanId: id);
});

class EmpLoanApplicationDetailsScreen extends ConsumerWidget {
  final String loanId;
  const EmpLoanApplicationDetailsScreen({super.key, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_empLoanDetailProvider(loanId));

    return WebScaffold(
      title: 'Loan Application Review',
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
    final status = data['status'] as String? ?? '';
    final canAssignDeliveryRider =
        status == 'approved' && data['disbursement_method'] == 'rider_delivery';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusHeader(data),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  flex: 3,
                  child: Column(children: [
                    _buildLenderInfo(data),
                    const SizedBox(height: 16),
                    _buildLoanInfo(data),
                    const SizedBox(height: 16),
                    _buildCoMakerCard(data),
                  ])),
              const SizedBox(width: 20),
              Expanded(
                  flex: 2,
                  child: Column(children: [
                    _buildAccountUpgradeStatus(data),
                    if (canAssignDeliveryRider) ...[
                      const SizedBox(height: 16),
                      _buildDisbursementAction(context, ref, data),
                    ],
                  ])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDisbursementAction(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) {
    return _SectionCard(
      title: 'Cash via Rider — Disbursement',
      subtitle: 'Assign an available rider to hand the cash to the lender',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The lender chose to receive the loan via a delivery rider.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () =>
                  _showAssignDeliveryRider(context, ref, data),
              icon: const Icon(Icons.delivery_dining, size: 18),
              label: const Text('Assign Delivery Rider'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAssignDeliveryRider(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => RiderDisburseAssignModal(
        loanId: data['id'] as String,
        loanAmount: (data['principal_amount'] as num?)?.toDouble() ?? 0,
        lenderName:
            '${data['lender']?['first_name'] ?? ''} ${data['lender']?['last_name'] ?? ''}'
                .trim(),
      ),
    );
    if (assigned == true && context.mounted) {
      context.showSnackBarAsToast(const SnackBar(
          content: Text('Delivery rider assigned'),
          backgroundColor: AppColors.success));
      ref.invalidate(_empLoanDetailProvider(loanId));
    }
  }

  Widget _buildStatusHeader(Map<String, dynamic> data) {
    return _SectionCard(
      title: 'Loan #${data['loan_number'] ?? '—'}',
      subtitle:
          'Applied: ${(data['created_at'] ?? '').toString().substring(0, 10)}',
      trailing: StatusBadge(
        status: (data['rider_delivery_assigned'] == true &&
                (data['status'] ?? 'pending') == 'approved')
            ? 'rider_delivery_assigned'
            : (data['status'] ?? 'pending'),
        large: true,
      ),
    );
  }

  Widget _buildLenderInfo(Map<String, dynamic> data) {
    final lender = data['lender'] as Map<String, dynamic>? ?? {};
    final profile = (data['lender_profile'] as Map<String, dynamic>?) ??
        (lender['lender_profiles'] as Map<String, dynamic>? ?? {});
    return _SectionCard(
      title: 'Lender Information',
      subtitle: 'Upgraded Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(
              'Name',
              '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'
                  .trim()),
          _row('Phone', lender['phone'] ?? '—'),
          _row('Email', lender['email'] ?? '—'),
          _row('Employment', profile['employment_type'] ?? '—'),
          _row(
              'Monthly Income',
              profile['monthly_income'] != null
                  ? '₱${profile['monthly_income']}'
                  : '—'),
          _row('Account Upgrade Status',
              profile['account_upgrade_status'] ?? '—'),
        ],
      ),
    );
  }

  Widget _buildLoanInfo(Map<String, dynamic> data) {
    return _SectionCard(
      title: 'Loan Details',
      subtitle: 'Terms & amounts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Principal',
              '₱${(data['principal_amount'] ?? 0).toStringAsFixed(2)}'),
          _row('Interest (20%)',
              '₱${(data['interest_amount'] ?? 0).toStringAsFixed(2)}'),
          _row('Total Payable',
              '₱${(data['total_payable'] ?? 0).toStringAsFixed(2)}'),
          _row('Frequency',
              ((data['frequency'] ?? data['payment_frequency']) ?? '')
                  .toString()
                  .toUpperCase()),
          _row('Loan Term', _loanTermLabel(data)),
          _row('Number of Payments', '${data['term_periods'] ?? '—'}'),
          _row('Installment',
              '₱${(data['installment_amount'] ?? 0).toStringAsFixed(2)}'),
          _row('Purpose', data['purpose'] ?? '—'),
        ],
      ),
    );
  }

  Widget _buildCoMakerCard(Map<String, dynamic> data) {
    final coMakers =
        (data['co_makers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (coMakers.isEmpty) return const SizedBox.shrink();
    final cm = coMakers.first;
    final signature = cm['signature'] as String?;
    return _SectionCard(
      title: 'Co-Maker',
      subtitle: 'Guarantor & signature',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Name',
              '${cm['first_name'] ?? ''} ${cm['last_name'] ?? ''}'.trim()),
          _row('Relationship', cm['relationship'] ?? '—'),
          _row('Phone', cm['phone_number'] ?? '—'),
          _row('Birthday', cm['date_of_birth'] ?? '—'),
          _row('Address', cm['address'] ?? '—'),
          if (signature != null && signature.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Co-Maker Signature',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              width: 280,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildSignatureImage(signature),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSignatureImage(String signature) {
    const placeholder = Center(
      child: Icon(Icons.draw_outlined,
          size: 40, color: AppColors.textTertiary),
    );
    if (signature.startsWith('data:') || signature.startsWith('http')) {
      return Image.network(
        signature,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    try {
      final bytes = base64Decode(signature);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholder,
      );
    } catch (_) {
      return placeholder;
    }
  }

  Widget _buildAccountUpgradeStatus(Map<String, dynamic> data) {
    final accountUpgrade = data['account_upgrade_status'] ?? 'unknown';
    return _SectionCard(
      title: 'Account Upgrade Verification',
      subtitle: 'Identity documents status',
      child: Row(children: [
        StatusBadge(status: accountUpgrade),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              accountUpgrade == 'verified'
                  ? 'Account upgrade documents verified'
                  : 'Account upgrade not yet verified',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ),
      ]),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary))),
      ]),
    );
  }

  String _loanTermLabel(Map<String, dynamic> data) {
    final frequency =
        (data['frequency'] ?? data['payment_frequency'] ?? '').toString();
    final unit = frequency.toLowerCase() == 'daily'
        ? 'days'
        : frequency.toLowerCase() == 'weekly'
            ? 'weeks'
            : 'months';
    final periods = (data['term_periods'] as num?)?.toInt() ?? 0;
    if (periods > 0) return '$periods $unit';
    final schedules = (data['loan_schedules'] as List?) ?? const [];
    if (schedules.isNotEmpty) return '${schedules.length} $unit';
    final days = data['term_days'];
    return days != null ? '$days days' : '—';
  }

  Widget _buildShimmer() => ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, __) => const ShimmerLoader(height: 180),
      );

}

/// White section card with a dark slate header strip — matches the card style
/// used on the Lender Account Upgrade Details screen.
class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? child;
  const _SectionCard({
    required this.title,
    this.subtitle = '',
    this.trailing,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF5C6370),
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white70),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          if (child != null)
            Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}
