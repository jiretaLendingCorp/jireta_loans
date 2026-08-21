// lib/presentation/features/lender/payments/screens/lender_office_payment_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../loans/providers/lender_loan_provider.dart';
import '../providers/lender_payment_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

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

class LenderOfficePaymentScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> extra;
  const LenderOfficePaymentScreen({super.key, required this.extra});

  @override
  ConsumerState<LenderOfficePaymentScreen> createState() => _State();
}

class _State extends ConsumerState<LenderOfficePaymentScreen> {
  bool _requesting = false;
  bool _requested = false;
  late String _scheduleId;
  late double _amount;
  late String _dueDate;

  @override
  void initState() {
    super.initState();
    _scheduleId = widget.extra['schedule_id'] as String? ?? '';
    _amount = (widget.extra['amount'] as num?)?.toDouble() ?? 0.0;
    _dueDate = widget.extra['due_date'] as String? ?? '';
    if (_scheduleId.isEmpty) Future.microtask(_resolveSchedule);
  }

  Future<void> _resolveSchedule() async {
    final loanId = widget.extra['loan_id'] as String? ?? '';
    if (loanId.isEmpty) return;
    await ref.read(lenderLoanProvider.notifier).loadLoanDetails(loanId);
    if (!mounted) return;
    final schedules = ref.read(lenderLoanProvider).selectedLoan?.schedules ?? [];
    Map<String, dynamic>? target;
    for (final s in schedules) {
      final status = (s['status'] ?? 'pending') as String;
      if (status == 'pending' || status == 'partial') {
        target = s;
        break;
      }
    }
    target ??= schedules.isEmpty ? null : schedules.first;
    final resolved = target;
    if (resolved != null && mounted) {
      setState(() {
        _scheduleId = resolved['id'] as String? ?? _scheduleId;
        _amount = (resolved['amount_due'] as num?)?.toDouble() ?? _amount;
        _dueDate = resolved['due_date'] as String? ?? _dueDate;
      });
    }
  }

  Future<void> _requestOfficeVisit() async {
    if (_scheduleId.isEmpty) {
      _showInfo('Missing installment information. Please try again.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request Office Visit'),
        content: const Text(
          'A request will be sent to our office so they expect your visit '
          'and can prepare your payment record. Continue?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Request')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _requesting = true);
    bool ok = false;
    try {
      ok = await ref
          .read(lenderPaymentProvider.notifier)
          .requestOfficePayment(loanScheduleId: _scheduleId);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _requesting = false;
      if (ok) _requested = true;
    });

    if (ok) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Request Sent'),
          content: const Text(
            'Our office has been notified of your visit. '
            'Pay at the office during business hours and our staff will '
            'record your payment and issue an official receipt.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
            TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(RouteConstants.lenderCollections);
                },
                child: const Text('View Requests')),
          ],
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Request Not Sent'),
          content: Text(
            ref.read(lenderPaymentProvider).error ??
                'Failed to submit your request. Please try again.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    }
  }

  void _showInfo(String message) {
    context.showSnackBarAsToast(
        SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      title: 'Pay at the Office',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.storefront_outlined,
                color: AppColors.info, size: 36),
          ),
          const SizedBox(height: 20),
          const Text('Office Payment',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
            'Visit our office during business hours to pay your installment '
            'in cash. Our staff will record your payment and issue an official '
            'receipt.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          if (_amount > 0)
            _StepRow(
                icon: Icons.attach_money,
                text: 'Prepare the amount of ${_amount.toCurrency}'),
          if (_dueDate.isNotEmpty)
            _StepRow(
                icon: Icons.event_outlined,
                text: 'Due date: $_dueDate'),
          const SizedBox(height: 16),
          const _StepRow(
              icon: Icons.location_on_outlined,
              text: 'Visit our office at the address shown in your profile.'),
          const SizedBox(height: 12),
          const _StepRow(
              icon: Icons.receipt_long_outlined,
              text: 'Pay the cashier and keep your official receipt.'),
          const SizedBox(height: 12),
          const _StepRow(
              icon: Icons.verified_outlined,
              text: 'Your schedule is updated instantly once the payment is '
                  'recorded.'),
          const SizedBox(height: 24),
          if (_requested)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.riderGreen.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: AppColors.riderGreen, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your office visit request has been sent. Our office '
                      'expects your visit.',
                      style: TextStyle(
                          color: AppColors.riderGreen, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _requesting ? null : _requestOfficeVisit,
                icon: _requesting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.storefront_outlined, size: 18),
                label: const Text('Request Office Visit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.lenderBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.info, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Please pay on or before the due date to avoid late fees.',
                    style: TextStyle(color: AppColors.info, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StepRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.lenderBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}