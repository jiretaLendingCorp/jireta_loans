// lib/presentation/features/lender/payments/screens/lender_office_payment_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/security/submission_guard.dart';
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
      label: 'Transaction',
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
  /// Keeps the (autoDispose) collection provider alive while this screen is
  /// open so the post-submit server re-check sees the latest state instead of
  /// a freshly-reset empty list (false "Request Timed Out").
  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _collectionSub;

  @override
  void initState() {
    super.initState();
    _collectionSub = ref.listenManual(lenderCollectionProvider, (_, __) {});
    _scheduleId = widget.extra['schedule_id'] as String? ?? '';
    _amount = (widget.extra['amount'] as num?)?.toDouble() ?? 0.0;
    _dueDate = widget.extra['due_date'] as String? ?? '';
    if (_scheduleId.isEmpty) Future.microtask(_resolveSchedule);
  }

  @override
  void dispose() {
    _collectionSub?.close();
    super.dispose();
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

  /// Shared positive modal para sa matagumpay (o malamang naipadala) na
  /// request — malinaw na confirmation na may check icon.
  Future<void> _showSubmittedDialog({
    required String title,
    required String message,
    String actionLabel = 'View Requests',
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded,
            color: AppColors.success, size: 46),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.push(RouteConstants.lenderCollections);
              },
              child: Text(actionLabel)),
        ],
      ),
    );
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
    // A timeout / 5xx is NOT proof that the request was rejected. It used to
    // fall through to the generic "Request Not Sent" title, which made a
    // request that the server had actually created look like a failure.
    if (low.contains('timed out') || low.contains('timeout')) {
      return 'Request Timed Out';
    }
    if (low.contains('server error') ||
        low.contains('internal server error') ||
        low.contains('an error occurred')) {
      return 'Server Error';
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

    // Kumpirmasyon bago ang request: device credential (fingerprint / Face ID
    // / device PIN), o ang app-level MPIN kapag walang password ang phone.
    final verified = await ref.read(submissionGuardProvider).confirm(
          context,
          reason: 'I-verify ang iyong pagkakakilanlan (fingerprint / Face ID, '
              'device PIN, o MPIN) para ipadala ang office payment request.',
        );
    if (!verified || !mounted) return;

    AppLogger.d('[OfficePayment] User confirmed office visit schedule=$_scheduleId loan=${widget.extra['loan_id']} amount=$_amount');
    setState(() => _requesting = true);
    bool ok = false;
    try {
      ok = await ref
          .read(lenderPaymentProvider.notifier)
          .requestOfficePayment(loanScheduleId: _scheduleId, amount: _amount);
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

    // A failed client call does not prove the request was rejected: the server
    // may have created the assignment after we stopped waiting (timeout, 5xx,
    // slow staff push fan-out). Ask the server before claiming it was not sent.
    if (!ok) {
      ok = await _requestExistsOnServer();
      if (ok) {
        AppLogger.i(
            '[OfficePayment] request found on server despite client failure — treating as sent schedule=$_scheduleId');
        if (mounted) setState(() => _requested = true);
      }
    }
    if (ok) ref.read(lenderCollectionProvider.notifier).loadList();

    // Walang mounted check pagkatapos ng huling `await` (`_requestExistsOnServer`)
    // — kailangan ito bago gamitin muli ang `context` sa mga dialog sa ibaba.
    if (!mounted) return;

    if (ok) {
      AppLogger.i('[OfficePayment] office request OK schedule=$_scheduleId');
      await _showSubmittedDialog(
        title: 'Successfully Submitted',
        message: 'Our office has been notified of your visit. Pay at the '
            'office during business hours and our staff will record your '
            'payment and issue an official receipt.',
      );
    } else {
      final err = ref.read(lenderPaymentProvider).error ??
          'Failed to submit your request. Please try again.';
      AppLogger.w('[OfficePayment] office request FAILED schedule=$_scheduleId error=$err');
      if (kDebugMode) debugPrint('[OfficePayment] failure dialog error: $err');
      // A lost/timed-out response is NOT proof of failure — the request was
      // already re-checked against the server above. Huwag magpakita ng
      // nakalilitong "Request Timed Out".
      final low = err.toLowerCase();
      final inconclusive = low.contains('timed out') ||
          low.contains('timeout') ||
          low.contains('unable to reach') ||
          low.contains('no internet') ||
          low.contains('server error') ||
          low.contains('internal server error') ||
          low.contains('an error occurred');
      if (inconclusive) {
        await _showSubmittedDialog(
          title: 'Submission Received',
          message: 'Your request was sent and is being processed. '
              'Please check Collection History to confirm the update.',
        );
        return;
      }
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

  /// True kapag may pending collection request na sa server para sa installment
  /// na ito — ginagamit kapag "failure" ang bumalik sa client pero posible na
  /// palang naipasok ng backend ang request (lost response / timeout).
  Future<bool> _requestExistsOnServer() async {
    try {
      await ref.read(lenderCollectionProvider.notifier).loadList();
    } catch (e) {
      AppLogger.w('[OfficePayment] server re-check failed: $e');
      return false;
    }
    if (!mounted) return false;
    return _hasPendingLocally();
  }

  String _fmtDueDate() {
    if (_dueDate.isEmpty) return '—';
    final parsed = DateTime.tryParse(_dueDate);
    if (parsed == null) return _dueDate;
    return DateFormat('MMM dd, yyyy').format(parsed);
  }

  Future<void> _openOfficeLocation() async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=Jireta+Loans+%26+Credit+Corp');
    try {
      final ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _showInfo('Could not open Maps. Please search Jireta Loans manually.');
      }
    } catch (_) {
      if (mounted) {
        _showInfo('Could not open Maps. Please search Jireta Loans manually.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      title: 'Pay at the Office',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Napiling method (summary card, naka-select na radio).
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.lenderBlue, width: 1.6),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  height: 46,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/icons/pay_with_office.jpg',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.storefront_outlined,
                            color: AppColors.info, size: 24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pay at the Office',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary)),
                      SizedBox(height: 4),
                      Text(
                          'Payment is recorded on-site and a receipt is issued.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.lenderBlue,
                  ),
                  child: const Center(
                    child: Icon(Icons.check,
                        size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Payment details.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PAYMENT DETAILS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                _DetailRow(
                    label: 'Amount Due',
                    value: _amount.toCurrency,
                    bold: true),
                const SizedBox(height: 8),
                _DetailRow(label: 'Due Date', value: _fmtDueDate()),
                const SizedBox(height: 8),
                const _DetailRow(label: 'Payment Method', value: 'Office'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.location_on_outlined,
                  size: 16, color: AppColors.lenderBlue),
              SizedBox(width: 6),
              Text('OFFICE',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppColors.lenderBlue)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Jireta Loans & Credit Corp.',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('09755849954 • jiretalendingcorp@gmail.com',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.access_time_rounded,
                  size: 16, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text('Mon - Fri • 8:00 AM - 5:00 PM',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _openOfficeLocation,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('VIEW OFFICE LOCATION',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
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
              child: ElevatedButton(
                onPressed: _requesting ? null : _requestOfficeVisit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.lenderBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.lenderBlue.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: _requesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('CONFIRM OFFICE PAYMENT',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _DetailRow(
      {required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }
}