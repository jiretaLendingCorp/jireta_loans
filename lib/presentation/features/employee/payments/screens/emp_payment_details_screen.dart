// lib/presentation/features/employee/payments/screens/emp_payment_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/emp_payment_provider.dart';

class EmpPaymentDetailsScreen extends ConsumerStatefulWidget {
  final String paymentId;
  const EmpPaymentDetailsScreen({super.key, required this.paymentId});

  @override
  ConsumerState<EmpPaymentDetailsScreen> createState() =>
      _EmpPaymentDetailsScreenState();
}

class _EmpPaymentDetailsScreenState
    extends ConsumerState<EmpPaymentDetailsScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ref
        .read(empPaymentListProvider.notifier)
        .getDetail(widget.paymentId);
    setState(() {
      _detail = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const WebScaffold(title: 'Payment Details', body: ShimmerLoader());
    }
    if (_detail == null) {
      return const WebScaffold(
          title: 'Payment Details',
          body: Center(child: Text('Payment not found.')));
    }

    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final amount = (_detail!['amount'] as num?)?.toDouble() ?? 0.0;
    final outstanding = (_detail!['outstanding_balance'] as num?)?.toDouble();

    return WebScaffold(
      title: 'Payment Details',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _card(
              'Payment Overview',
              [
                _row('Payment #', _detail!['id'] ?? '-'),
                _row('Loan Number', _detail!['loan_number'] ?? '-'),
                _row('Lender', _detail!['lender_name'] ?? '-'),
                _row('Status', '', badge: _detail!['status'] as String?),
                _row('Amount', '₱${fmt.format(amount)}'),
                if (outstanding != null)
                  _row('Remaining Balance After Payment',
                      '₱${fmt.format(outstanding)}'),
              ],
            ),
            const SizedBox(height: 16),
            _card(
              'Payment Method & Reference',
              [
                _row('Method', _methodLabel(_detail!['payment_method'] ?? '')),
                if (_detail!['reference_number'] != null)
                  _row('Reference #', _detail!['reference_number']),
                if (_detail!['xendit_payment_id'] != null)
                  _row('Xendit ID', _detail!['xendit_payment_id']),
                _row('Recorded By', _detail!['recorded_by_name'] ?? '-'),
                _row('Date', _detail!['created_at'] ?? '-'),
                if (_detail!['notes'] != null) _row('Notes', _detail!['notes']),
              ],
            ),
            if (_detail!['reversed_at'] != null) ...[
              const SizedBox(height: 16),
              _card(
                'Reversal Details',
                [
                  _row('Reversed At', _detail!['reversed_at']),
                  _row('Reversed By', _detail!['reversed_by_name'] ?? '-'),
                  _row('Reversal Reason', _detail!['reversal_reason'] ?? '-'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.deepNavy)),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {String? badge}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 200,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 12),
          badge != null
              ? StatusBadge(status: badge)
              : Expanded(
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary)),
                ),
        ],
      ),
    );
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'gcash':
        return 'GCash';
      case 'office_cash':
      case 'cash':
        return 'Office';
      case 'rider_collection':
        return 'Rider Collection';
      case 'gcash_xendit':
        return 'GCash';
      default:
        return m;
    }
  }
}
