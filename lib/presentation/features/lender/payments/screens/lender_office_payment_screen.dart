// lib/presentation/features/lender/payments/screens/lender_office_payment_screen.dart
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

  Future<void> _requestOfficeVisit() async {
    if (_scheduleId.isEmpty) {
      AppLogger.w('[OfficePayment] _requestOfficeVisit empty schedule_id extra=${widget.extra}');
      _showInfo('Missing installment information. Please return to Payment Schedule and tap Pay again.');
      return;
    }
    if (!_validateAmount()) return;
    if (_hasPendingLocally()) {
      AppLogger.d('[OfficePayment] _hasPendingLocally true for $_scheduleId — skipping server call');
      await _showPendingDialog();
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

    final customAmt = _customAmount;
    AppLogger.d('[OfficePayment] User confirmed office visit schedule=$_scheduleId loan=${widget.extra['loan_id']} amount=$customAmt');
    setState(() => _requesting = true);
    bool ok = false;
    try {
      ok = await ref
          .read(lenderPaymentProvider.notifier)
          .requestOfficePayment(loanScheduleId: _scheduleId, amount: customAmt);
    } catch (e, st) {
      AppLogger.e('[OfficePayment] requestOfficePayment threw', e, st);
      if (kDebugMode) debugPrint('[OfficePayment] exception: $e');
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _requesting = false;
      if (ok) _requested = true;
    });
    if (ok) ref.read(lenderCollectionProvider.notifier).loadList();

    if (ok) {
      AppLogger.i('[OfficePayment] office request OK schedule=$_scheduleId');
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
      final err = ref.read(lenderPaymentProvider).error ??
          'Failed to submit your request. Please try again.';
      AppLogger.w('[OfficePayment] office request FAILED schedule=$_scheduleId error=$err');
      if (kDebugMode) debugPrint('[OfficePayment] failure dialog error: $err');
      final title = _titleForError(err);
      final isPending = title == 'Already Pending';
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

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      title: 'Pay at the Office',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
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
          // Flexible amount – lender chooses how much to pay
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _amountError != null ? AppColors.error : AppColors.border),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
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
                Text(
                  _outstandingBalance != null
                      ? 'Outstanding: ${_outstandingBalance!.toCurrency} • Installment: ${_amount.toCurrency}'
                      : 'Installment: ${_amount.toCurrency}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                const Text('Enter any amount – partial or advance supported. System allocates across installments.',
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
                if (_dueDate.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.event_outlined, size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Text('Due: $_dueDate', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ]),
                ],
              ],
            ),
          ),
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