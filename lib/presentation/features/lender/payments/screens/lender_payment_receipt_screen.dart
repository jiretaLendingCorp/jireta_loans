// lib/presentation/features/lender/payments/screens/lender_payment_receipt_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/lender_payment_provider.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
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

final _receiptProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, paymentId) async {
  return await ref
      .read(lenderPaymentProvider.notifier)
      .getReceiptData(paymentId);
});

class LenderPaymentReceiptScreen extends ConsumerWidget {
  final String paymentId;
  const LenderPaymentReceiptScreen({super.key, required this.paymentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_receiptProvider(paymentId));

    return MobileScaffold(
      title: 'Payment Receipt',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: async.when(
        loading: () => const ShimmerLoader(),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.receipt_long,
                  size: 64, color: AppColors.textTertiary),
              const SizedBox(height: 16),
              Text('Unable to load receipt: $e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(_receiptProvider(paymentId)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.lenderBlue),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (data) => _buildReceipt(context, ref, data),
      ),
    );
  }

  Widget _buildReceipt(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) {
    final receiptUrl = data['receipt_url'] as String?;
    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final method = data['payment_method'] as String? ?? '';
    final status = data['status'] as String? ?? '';
    final refNum = data['reference_number'] as String? ?? '';
    final paidAt = data['created_at'] as String?;
    final loanNum = data['loan_number'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _ReceiptCard(
            amount: amount,
            method: method,
            status: status,
            refNum: refNum,
            paidAt: paidAt,
            loanNum: loanNum,
          ),
          const SizedBox(height: 20),
          if (receiptUrl != null) ...[
            AppButton(
              label: 'Download Receipt',
              icon: Icons.download_outlined,
              backgroundColor: AppColors.lenderBlue,
              onPressed: () async {
                final uri = Uri.parse(receiptUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Share Receipt',
              icon: Icons.share_outlined,
              variant: AppButtonVariant.outlined,
              outlineColor: AppColors.lenderBlue,
              textColor: AppColors.lenderBlue,
              onPressed: () async {
                final uri = Uri.parse(receiptUrl);
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'Receipt is being generated. Please check back shortly.',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary))),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final double amount;
  final String method, status, refNum, loanNum;
  final String? paidAt;

  const _ReceiptCard(
      {required this.amount,
      required this.method,
      required this.status,
      required this.refNum,
      required this.loanNum,
      this.paidAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [AppColors.lenderBlue, AppColors.lenderBlueLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(28)),
                  child: const Icon(Icons.receipt_long,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(height: 12),
                const Text('Payment Receipt',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(amount.toCurrency,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
                const SizedBox(height: 8),
                StatusBadge(status: status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _Row('Loan Number', loanNum.isNotEmpty ? loanNum : '-'),
                const Divider(height: 16),
                _Row(
                    'Payment Method',
                    method == 'gcash' || method == 'gcash_xendit'
                        ? 'GCash'
                        : method == 'office_cash' || method == 'cash'
                            ? 'Office'
                            : method == 'rider_collection'
                                ? 'Rider Collection'
                                : method.replaceAll('_', ' ')),
                const Divider(height: 16),
                if (refNum.isNotEmpty) ...[
                  _Row('Reference No.', refNum),
                  const Divider(height: 16),
                ],
                if (paidAt != null)
                  _Row('Date & Time',
                      DateTime.tryParse(paidAt!)?.toShortDate ?? '-'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }
}
