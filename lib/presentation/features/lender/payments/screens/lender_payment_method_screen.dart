// lib/presentation/features/lender/payments/screens/lender_payment_method_screen.dart
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

class LenderPaymentMethodScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> extra;
  const LenderPaymentMethodScreen({super.key, required this.extra});

  @override
  ConsumerState<LenderPaymentMethodScreen> createState() => _State();
}

class _State extends ConsumerState<LenderPaymentMethodScreen> {
  bool _requesting = false;
  late String _scheduleId;
  late double _amount;
  late String _dueDate;

  @override
  void initState() {
    super.initState();
    _scheduleId = widget.extra['schedule_id'] as String? ?? '';
    _amount = (widget.extra['amount'] as num?)?.toDouble() ?? 0.0;
    _dueDate = widget.extra['due_date'] as String? ?? '';
    // When arriving with only a loan (e.g. from the dashboard card), resolve the
    // next payable installment so the cash-collection request has a schedule.
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

  Future<void> _requestCashCollection() async {
    if (_scheduleId.isEmpty) {
      _showInfo('Missing installment information. Please try again.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request Rider Collection'),
        content: const Text(
          'A rider will visit your home to collect the payment. '
          'Our office will assign a rider and notify you. Continue?',
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
          .requestRiderCollection(loanScheduleId: _scheduleId);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _requesting = false);

    if (ok) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Collection Requested'),
          content: const Text(
            'Your rider collection request has been submitted. '
            'Our office will assign a rider and notify you. '
            'You can track the collection under Collection History.',
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
                child: const Text('View Collections')),
          ],
        ),
      );
    } else {
      // Dialog instead of a toast: it can never be missed, and it carries the
      // server's actual reason (e.g. already-in-progress, loan not payable).
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

  void _showComingSoon() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('GCash Payment'),
        content: const Text(
          'GCash payment is coming soon. Please use Cash (rider collection) '
          'or pay at our office for now.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      title: 'Payment Method',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.lenderBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Amount Due',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(_amount.toCurrency,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                if (_dueDate.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Due: $_dueDate',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _MethodCard(
            icon: Icons.home_work_outlined,
            color: AppColors.riderGreen,
            title: 'Cash — Rider Collection',
            subtitle:
                'A rider will visit your home to collect the payment. Our office assigns the rider and notifies you.',
            badge: null,
            onTap: _requesting ? null : _requestCashCollection,
            loading: _requesting,
          ),
          const SizedBox(height: 12),
          _MethodCard(
            icon: Icons.storefront_outlined,
            color: AppColors.info,
            title: 'Pay at the Office',
            subtitle:
                'Visit our office to pay in cash. Payment will be recorded on-site and a receipt will be issued.',
            badge: null,
            onTap: () => context.push(RouteConstants.lenderOfficePayment,
                extra: {
                  'loan_id': widget.extra['loan_id'],
                  'schedule_id': _scheduleId,
                  'amount': _amount,
                  'due_date': _dueDate,
                }),
          ),
          const SizedBox(height: 12),
          _MethodCard(
            icon: Icons.account_balance_wallet,
            color: const Color(0xFF007DFF),
            title: 'GCash',
            subtitle: 'Pay securely via GCash through our payment partner.',
            badge: 'Coming Soon',
            onTap: _showComingSoon,
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback? onTap;
  final bool loading;

  const _MethodCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.textPrimary)),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(badge!,
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.warning)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                const Icon(Icons.chevron_right,
                    color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}