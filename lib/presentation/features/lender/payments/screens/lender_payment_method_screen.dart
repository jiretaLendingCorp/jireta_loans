// lib/presentation/features/lender/payments/screens/lender_payment_method_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/logger.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../loans/providers/lender_loan_provider.dart';
import '../../collections/providers/lender_collection_provider.dart';
import '../providers/lender_payment_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
  MobileNavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'History',
      route: RouteConstants.lenderPaymentHistory),

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
  final _amountCtrl = TextEditingController();
  double? _outstandingBalance;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _scheduleId = widget.extra['schedule_id'] as String? ?? '';
    _amount = (widget.extra['amount'] as num?)?.toDouble() ?? 0.0;
    _dueDate = widget.extra['due_date'] as String? ?? '';
    _amountCtrl.text = _amount > 0 ? _amount.toStringAsFixed(2) : '';
    // When arriving with only a loan (e.g. from the dashboard card), resolve the
    // next payable installment so the cash-collection request has a schedule.
    if (_scheduleId.isEmpty) Future.microtask(_resolveSchedule);
    Future.microtask(_loadOutstanding);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOutstanding() async {
    final loanId = widget.extra['loan_id'] as String? ?? '';
    if (loanId.isEmpty) return;
    try {
      await ref.read(lenderLoanProvider.notifier).loadLoanDetails(loanId);
      final bal = ref.read(lenderLoanProvider).selectedLoan?.outstandingBalance ?? 0;
      if (mounted) setState(() => _outstandingBalance = bal);
    } catch (_) {}
  }

  double? get _customAmount {
    final v = double.tryParse(_amountCtrl.text.trim());
    if (v == null || v <= 0) return null;
    return v;
  }

  bool _validateAmount() {
    final v = double.tryParse(_amountCtrl.text.trim());
    if (v == null || v <= 0) {
      setState(() => _amountError = 'Enter a valid amount (> 0)');
      return false;
    }
    if (_outstandingBalance != null && v > _outstandingBalance! + 0.01) {
      setState(() => _amountError = 'Exceeds outstanding ${_outstandingBalance!.toCurrency}');
      return false;
    }
    setState(() => _amountError = null);
    return true;
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
      final amt = (resolved['amount_due'] as num?)?.toDouble() ?? _amount;
      setState(() {
        _scheduleId = resolved['id'] as String? ?? _scheduleId;
        _amount = amt;
        _amountCtrl.text = amt > 0 ? amt.toStringAsFixed(2) : _amountCtrl.text;
        _dueDate = resolved['due_date'] as String? ?? _dueDate;
      });
    }
  }

  bool _hasPendingLocally() {
    final colState = ref.read(lenderCollectionProvider);
    final raw = colState.valueOrNull;
    final items = (raw?['items'] as List?) ?? (raw?['data'] as List?) ?? [];
    for (final item in items) {
      if (item is! Map) continue;
      final sid = (item['loan_schedule_id'] as String?) ??
          (item['loan_schedule'] is Map
              ? (item['loan_schedule'] as Map)['id'] as String?
              : null) ??
          '';
      final status = item['status'] as String? ?? '';
      if (sid == _scheduleId &&
          ['requested', 'assigned', 'accepted', 'in_progress']
              .contains(status)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _showPendingDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Already Pending'),
        content: const Text('You have already pending payment'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  String _titleForError(String err) {
    final low = err.toLowerCase();
    if (low.contains('already pending')) return 'Already Pending';
    if (low.contains('not yet ready') || low.contains('not in a payable')) {
      return 'Loan Not Ready';
    }
    if (low.contains('already fully paid') || low.contains('already paid')) {
      return 'Already Paid';
    }
    if (low.contains('session') && low.contains('expired') ||
        low.contains('log in again')) {
      return 'Session Expired';
    }
    if (low.contains('no internet') || low.contains('unable to reach')) {
      return 'Connection Error';
    }
    if (low.contains('not found') || low.contains('installment not found')) {
      return 'Not Found';
    }
    if (low.contains('access denied') || low.contains('permission')) {
      return 'Access Denied';
    }
    return 'Request Not Sent';
  }

  Future<void> _requestCashCollection() async {
    if (_scheduleId.isEmpty) {
      AppLogger.w('[PaymentMethod] _requestCashCollection called with empty schedule_id extra=${widget.extra}');
      _showInfo('Missing installment information. Please return to Payment Schedule and tap Pay again.');
      return;
    }
    if (!_validateAmount()) return;
    // Client-side guard: if we already know this schedule has a pending
    // collection, show the pending message immediately without a round-trip.
    // The server is still the source of truth (see the 200/409 handlers below),
    // but this avoids the spinner when we can answer locally.
    if (_hasPendingLocally()) {
      AppLogger.d('[PaymentMethod] _hasPendingLocally true for $_scheduleId — skipping server call');
      await _showPendingDialog();
      return;
    }
    final customAmt = _customAmount;
    final displayAmt = (customAmt ?? _amount).toCurrency;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request Rider Collection'),
        content: Text(
          'A rider will visit your home to collect $displayAmt. '
          'Amount is flexible: you may pay partial, exact, or advance to next installments. Continue?',
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

    AppLogger.d('[PaymentMethod] User confirmed rider collection schedule=$_scheduleId loan=${widget.extra['loan_id']} amount=$customAmt');
    setState(() => _requesting = true);
    bool ok = false;
    try {
      ok = await ref
          .read(lenderPaymentProvider.notifier)
          .requestRiderCollection(loanScheduleId: _scheduleId, amount: customAmt);
    } catch (e, st) {
      AppLogger.e('[PaymentMethod] requestRiderCollection threw', e, st);
      if (kDebugMode) debugPrint('[PaymentMethod] exception: $e');
      ok = false;
    }
    if (!mounted) return;
    setState(() => _requesting = false);
    // Keep the schedule screen's pending chip in sync even before realtime.
    if (ok) ref.read(lenderCollectionProvider.notifier).loadList();

    if (ok) {
      AppLogger.i('[PaymentMethod] rider request OK schedule=$_scheduleId');
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
      final err = ref.read(lenderPaymentProvider).error ??
          'Failed to submit your request. Please try again.';
      AppLogger.w('[PaymentMethod] rider request FAILED schedule=$_scheduleId error=$err');
      if (kDebugMode) debugPrint('[PaymentMethod] failure dialog error: $err');
      final title = _titleForError(err);
      final isPending = title == 'Already Pending';
      // Dialog instead of a toast: it can never be missed, and it carries the
      // server's actual reason (e.g. already-in-progress, loan not payable).
      // The provider now maps backend codes to friendly sentences so this always
      // shows the "proper error" (e.g. Loan Not Ready, Already Paid) instead of
      // a generic "Request Not Sent".
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(isPending
              ? 'You have already pending payment'
              : err),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
                const Text('Installment Amount',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(_amount.toCurrency,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                if (_outstandingBalance != null) ...[
                  const SizedBox(height: 4),
                  Text('Outstanding: ${_outstandingBalance!.toCurrency}',
                      style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
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
          // Flexible amount input – lender can pay any amount
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _amountError != null ? AppColors.error : AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.payments_rounded, size: 16, color: AppColors.lenderBlue),
                  SizedBox(width: 6),
                  Text('Amount to Pay', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                ]),
                const SizedBox(height: 6),
                const Text('Enter any amount – partial, exact, or advance. System will allocate across installments.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: '₱ ',
                    hintText: 'e.g. ${_amount.toStringAsFixed(2)}',
                    errorText: _amountError,
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _amountError != null ? AppColors.error : AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.lenderBlue, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => setState(() => _amountError = null),
                ),
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
            onTap: () {
              if (!_validateAmount()) return;
              if (_hasPendingLocally()) {
                _showPendingDialog();
                return;
              }
              final amt = _customAmount ?? _amount;
              context.push(RouteConstants.lenderOfficePayment, extra: {
                'loan_id': widget.extra['loan_id'],
                'schedule_id': _scheduleId,
                'amount': amt,
                'due_date': _dueDate,
              });
            },
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