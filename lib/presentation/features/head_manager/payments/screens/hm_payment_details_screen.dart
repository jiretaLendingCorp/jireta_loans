// lib/presentation/features/head_manager/payments/screens/hm_payment_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/hm_payment_provider.dart';

final _paymentDetailFutureProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) async {
  final ds = sl<PaymentRemoteDataSource>();
  try {
    final p = await ds.getPaymentDetail(id);
    return {
      'id': p.id,
      'status': p.status,
      'method': p.method,
      'amount': p.amount,
      'created_at': p.createdAt.toIso8601String(),
      'reference_number': p.referenceNumber,
      'xendit_payment_id': p.xenditPaymentId,
      'notes': p.notes,
      'loan': p.loan,
      'recorded_by_user': p.recordedByUser,
    };
  } catch (_) {
    return null;
  }
});

class HmPaymentDetailsScreen extends ConsumerStatefulWidget {
  final String paymentId;
  const HmPaymentDetailsScreen({super.key, required this.paymentId});

  @override
  ConsumerState<HmPaymentDetailsScreen> createState() =>
      _HmPaymentDetailsScreenState();
}

class _HmPaymentDetailsScreenState
    extends ConsumerState<HmPaymentDetailsScreen> {
  bool _reversing = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_paymentDetailFutureProvider(widget.paymentId));
    return WebScaffold(
      title: 'Payment Details',
      body: async.when(
        loading: () => const Center(child: ShimmerLoader()),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (d) => d == null
            ? const Center(child: Text('Payment not found'))
            : _buildBody(context, d),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> d) {
    final status = d['status'] ?? '';
    final method = d['method'] ?? '';
    final amount = (d['amount'] as num?)?.toDouble() ?? 0;
    final createdAt =
        d['created_at'] != null ? DateTime.tryParse(d['created_at']) : null;
    final loan = d['loan'] as Map<String, dynamic>?;
    final recordedByUser = d['recorded_by_user'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment #${d['reference_number'] ?? d['id']?.toString().substring(0, 8) ?? ''}',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.deepNavy),
                    ),
                    const SizedBox(height: 4),
                    if (createdAt != null)
                      Text(
                        DateFormat('MMM dd, yyyy hh:mm a').format(createdAt),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              StatusBadge(status: status),
              if (status == 'verified')
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: ElevatedButton.icon(
                    onPressed: _reversing
                        ? null
                        : () => _reversePayment(context, d['id']),
                    icon: _reversing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.undo, size: 16),
                    label: const Text('Reverse'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Payment Information',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: AppColors.deepNavy)),
                  const Divider(height: 24),
                  _row('Amount', amount.toCurrency),
                  _row('Method', _methodLabel(method)),
                  _row('Status', status.toUpperCase()),
                  if (d['reference_number'] != null)
                    _row('Reference #', d['reference_number']),
                  if (d['xendit_payment_id'] != null)
                    _row('Xendit ID', d['xendit_payment_id']),
                  if (d['notes'] != null) _row('Notes', d['notes']),
                  if (createdAt != null)
                    _row('Date',
                        DateFormat('MMM dd, yyyy hh:mm a').format(createdAt)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (loan != null)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Loan Information',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppColors.deepNavy)),
                    const Divider(height: 24),
                    _row('Loan #', loan['loan_number'] ?? ''),
                    _row(
                        'Total Payable',
                        ((loan['total_payable'] as num?)?.toDouble() ?? 0)
                            .toCurrency),
                    _row(
                        'Outstanding Balance',
                        ((loan['outstanding_balance'] as num?)?.toDouble() ?? 0)
                            .toCurrency),
                    _row('Status', loan['status'] ?? ''),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (recordedByUser != null)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recorded By',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppColors.deepNavy)),
                    const Divider(height: 24),
                    _row(
                        'Name',
                        '${recordedByUser['first_name'] ?? ''} ${recordedByUser['last_name'] ?? ''}'
                            .trim()),
                    _row('Role', recordedByUser['role'] ?? ''),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _reversePayment(BuildContext context, String? paymentId) async {
    if (paymentId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => const ConfirmationDialog(
        title: 'Reverse Payment',
        message:
            'Are you sure you want to reverse this payment? This action cannot be undone.',
        confirmLabel: 'Reverse',
        confirmColor: AppColors.error,
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _reversing = true);
    try {
      final notifier = ref.read(hmPaymentProvider.notifier);
      final ok = await notifier.reverse(
          paymentId: paymentId, reason: 'Manual reversal by Head Manager');
      if (!mounted) return;
      if (ok) {
        if (!context.mounted) return;
        showDialog(
            context: context,
            builder: (_) =>
                const SuccessDialog(message: 'Payment reversed successfully.'));
        ref.invalidate(_paymentDetailFutureProvider(widget.paymentId));
      } else {
        if (!context.mounted) return;
        showDialog(
            context: context,
            builder: (_) =>
                const ErrorDialog(message: 'Failed to reverse payment.'));
      }
    } finally {
      if (mounted) setState(() => _reversing = false);
    }
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'gcash':
        return 'GCash';
      case 'office_cash':
        return 'Office Cash';
      case 'rider_collection':
        return 'Rider Collection';
      default:
        return method;
    }
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 180,
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary))),
          ],
        ),
      );
}
