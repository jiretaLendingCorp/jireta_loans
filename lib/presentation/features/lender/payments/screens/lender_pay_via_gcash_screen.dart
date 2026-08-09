// lib/presentation/features/lender/payments/screens/lender_pay_via_gcash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
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

class LenderPayViaGcashScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> extra;
  const LenderPayViaGcashScreen({super.key, required this.extra});

  @override
  ConsumerState<LenderPayViaGcashScreen> createState() => _State();
}

class _State extends ConsumerState<LenderPayViaGcashScreen> {
  String? _paymentUrl;
  bool _isGenerating = false;
  bool _paymentInitiated = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_generateLink);
  }

  Future<void> _generateLink() async {
    final loanId = widget.extra['loan_id'] as String? ?? '';
    final scheduleId = widget.extra['schedule_id'] as String? ?? '';
    if (loanId.isEmpty) {
      setState(() => _error = 'Missing loan information.');
      return;
    }
    setState(() {
      _isGenerating = true;
      _error = null;
    });
    final url =
        await ref.read(lenderPaymentProvider.notifier).generateGcashLink(
              loanId: loanId,
              loanScheduleId: scheduleId,
            );
    setState(() {
      _isGenerating = false;
      _paymentUrl = url;
      if (url == null) {
        _error = 'Failed to generate payment link. Please try again.';
      }
    });
  }

  Future<void> _openGcash() async {
    if (_paymentUrl == null) return;
    final uri = Uri.parse(_paymentUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      setState(() => _paymentInitiated = true);
    } else {
      setState(() => _error = 'Could not open payment link. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      title: 'Pay via GCash',
      accentColor: AppColors.lenderPurple,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFF007DFF).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_wallet,
                  size: 48, color: Color(0xFF007DFF)),
            ),
            const SizedBox(height: 24),
            const Text('GCash Payment',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text(
              'Tap the button below to open GCash and complete your payment securely via Xendit.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 36),
            if (_isGenerating)
              const Column(
                children: [
                  CircularProgressIndicator(color: AppColors.lenderPurple),
                  SizedBox(height: 16),
                  Text('Generating payment link...',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              )
            else if (_error != null)
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(_error!,
                                style:
                                    const TextStyle(color: AppColors.error))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppButton(
                      label: 'Retry',
                      onPressed: _generateLink,
                      color: AppColors.lenderPurple),
                ],
              )
            else if (_paymentUrl != null)
              Column(
                children: [
                  if (_paymentInitiated) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: AppColors.success),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Payment initiated. Your balance will update automatically once confirmed.',
                              style: TextStyle(
                                  color: AppColors.success, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  AppButton(
                    label:
                        _paymentInitiated ? 'Open GCash Again' : 'Open GCash',
                    onPressed: _openGcash,
                    color: const Color(0xFF007DFF),
                    icon: Icons.open_in_new,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
