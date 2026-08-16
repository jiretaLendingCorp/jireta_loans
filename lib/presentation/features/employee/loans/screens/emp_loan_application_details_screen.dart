// lib/presentation/features/employee/loans/screens/emp_loan_application_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../head_manager/ci/widgets/ci_assign_modal.dart';
import '../../../head_manager/disbursements/widgets/rider_disburse_assign_modal.dart';
import '../providers/emp_loan_provider.dart';

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
    final canAct = [
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    ].contains(status);
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
                  ])),
              const SizedBox(width: 20),
              Expanded(
                  flex: 2,
                  child: Column(children: [
                    _buildAccountUpgradeStatus(data),
                    const SizedBox(height: 16),
                    if (canAct) _buildActionPanel(context, ref, data),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cash via Rider — Disbursement',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy)),
            const Divider(height: 20),
            const Text(
              'The lender chose to receive the loan via a delivery rider. Assign an available rider to hand the cash to the lender.',
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Delivery rider assigned'),
          backgroundColor: AppColors.success));
      ref.invalidate(_empLoanDetailProvider(loanId));
    }
  }

  Widget _buildStatusHeader(Map<String, dynamic> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loan #${data['loan_number'] ?? '—'}',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.deepNavy)),
                  const SizedBox(height: 4),
                  Text(
                      'Applied: ${(data['created_at'] ?? '').toString().substring(0, 10)}',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
            StatusBadge(
              status: (data['rider_delivery_assigned'] == true &&
                      (data['status'] ?? 'pending') == 'approved')
                  ? 'rider_delivery_assigned'
                  : (data['status'] ?? 'pending'),
              large: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLenderInfo(Map<String, dynamic> data) {
    final lender = data['lender'] as Map<String, dynamic>? ?? {};
    final profile = lender['lender_profiles'] as Map<String, dynamic>? ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Lender Information',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy)),
            const Divider(height: 20),
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
            _row('GCash', profile['gcash_number'] ?? '—'),
            _row('Account Upgrade Status',
                profile['account_upgrade_status'] ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _buildLoanInfo(Map<String, dynamic> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Loan Details',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy)),
            const Divider(height: 20),
            _row('Principal',
                '₱${(data['principal_amount'] ?? 0).toStringAsFixed(2)}'),
            _row('Interest (20%)',
                '₱${(data['interest_amount'] ?? 0).toStringAsFixed(2)}'),
            _row('Total Payable',
                '₱${(data['total_payable'] ?? 0).toStringAsFixed(2)}'),
            _row('Frequency', (data['frequency'] ?? '').toUpperCase()),
            _row('Loan Term', _loanTermLabel(data)),
            _row('Number of Payments', '${data['term_periods'] ?? '—'}'),
            _row('Installment',
                '₱${(data['installment_amount'] ?? 0).toStringAsFixed(2)}'),
            _row('Purpose', data['purpose'] ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountUpgradeStatus(Map<String, dynamic> data) {
    final accountUpgrade = data['account_upgrade_status'] ?? 'unknown';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Account Upgrade Verification',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy)),
            const Divider(height: 20),
            Row(children: [
              StatusBadge(status: accountUpgrade),
              const SizedBox(width: 8),
              Text(
                  accountUpgrade == 'verified'
                      ? 'Account upgrade documents verified'
                      : 'Account upgrade not yet verified',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPanel(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) {
    final status = data['status'] as String? ?? '';
    final canApprove = [
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    ].contains(status);
    final canAssignCi =
        ['pending', 'under_review', 'ci_required'].contains(status);
    final canRequestCi = status == 'under_review';
    final canReject = [
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    ].contains(status);
    final canCancel = ['pending', 'under_review'].contains(status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Actions',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy)),
            const Divider(height: 20),
            if (canApprove)
              _actionBtn(
                  'Approve Loan',
                  AppColors.success,
                  Icons.check_circle_outline,
                  () => _approve(context, ref, data)),
            if (canAssignCi) ...[
              if (canApprove) const SizedBox(height: 10),
              _actionBtn('Assign Rider for CI', AppColors.gold, Icons.search,
                  () => _showAssignRider(context, ref, data)),
            ],
            if (canRequestCi) ...[
              const SizedBox(height: 10),
              _actionBtn('Request CI', AppColors.lenderBlue, Icons.search,
                  () => _requestCI(context, ref, data)),
            ],
            if (canReject) ...[
              const SizedBox(height: 10),
              _actionBtn('Reject Loan', AppColors.error, Icons.cancel_outlined,
                  () => _reject(context, ref, data)),
            ],
            if (canCancel) ...[
              const SizedBox(height: 10),
              _actionBtn('Cancel', AppColors.textSecondary, Icons.close,
                  () => _cancel(context, ref, data)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showAssignRider(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => CiAssignModal(loanId: data['id'] as String),
    );
    if (assigned == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rider assigned for credit investigation'),
          backgroundColor: AppColors.success));
      ref.invalidate(_empLoanDetailProvider(loanId));
    }
  }

  Widget _actionBtn(
      String label, Color color, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  String _loanTermLabel(Map<String, dynamic> data) {
    final periods = (data['term_periods'] as num?)?.toInt() ?? 0;
    final frequency = (data['frequency'] as String? ?? '').toLowerCase();
    final unit = frequency == 'daily'
        ? 'days'
        : frequency == 'weekly'
            ? 'weeks'
            : 'months';
    if (periods > 0) return '$periods $unit';
    final days = data['term_days'];
    return days != null ? '$days days' : '—';
  }

  Widget _buildShimmer() => ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, __) => const ShimmerLoader(height: 180),
      );

  Future<void> _approve(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => ConfirmationDialog(
            title: 'Approve Loan',
            message: 'Approve loan #${data['loan_number']}?'));
    if (ok == true && context.mounted) {
      final success = await ref
          .read(empLoanProvider.notifier)
          .approve(data['id'] as String);
      if (context.mounted) {
        if (success) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Loan approved'),
              backgroundColor: AppColors.success));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Failed to approve'),
              backgroundColor: AppColors.error));
        }
      }
    }
  }

  Future<void> _requestCI(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => const ConfirmationDialog(
            title: 'Request CI', message: 'Move to Credit Investigation?'));
    if (ok == true && context.mounted) {
      await ref.read(empLoanProvider.notifier).requestCI(data['id'] as String);
      if (context.mounted) ref.invalidate(_empLoanDetailProvider(loanId));
    }
  }

  Future<void> _reject(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Reject Loan'),
              content: TextField(
                  controller: reasonCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Reason for rejection'),
                  maxLines: 3),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error),
                    child: const Text('Reject')),
              ],
            ));
    if (ok == true && context.mounted) {
      await ref
          .read(empLoanProvider.notifier)
          .reject(data['id'] as String, reasonCtrl.text.trim());
      if (context.mounted) context.pop();
    }
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => const ConfirmationDialog(
            title: 'Cancel Application',
            message: 'Cancel this loan application?'));
    if (ok == true && context.mounted) {
      await ref.read(empLoanProvider.notifier).cancel(data['id'] as String);
      if (context.mounted) context.pop();
    }
  }
}
