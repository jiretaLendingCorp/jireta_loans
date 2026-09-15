// lib/presentation/features/lender/payments/screens/lender_payment_method_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/security/submission_guard.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/logger.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
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
  /// Napiling payment method via radio ('rider' | 'office'). GCash disabled.
  String _selected = 'rider';
  /// True habang nire-resolve ang installment (galing loan_id lang ang extra).
  /// Habang true, disabled ang Pay para hindi mag-toast ng "Missing...".
  bool _resolving = false;
  /// Keeps the (autoDispose) collection provider alive while this screen is
  /// open so the post-submit server re-check can read its latest state
  /// instead of a freshly-reset empty list (which caused a false
  /// "Request Timed Out" on requests that had actually succeeded).
  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _collectionSub;

  @override
  void initState() {
    super.initState();
    _collectionSub = ref.listenManual(lenderCollectionProvider, (_, __) {});
    _scheduleId = widget.extra['schedule_id'] as String? ?? '';
    _amount = (widget.extra['amount'] as num?)?.toDouble() ?? 0.0;
    _dueDate = widget.extra['due_date'] as String? ?? '';
    // When arriving with only a loan (e.g. from the dashboard card), resolve the
    // next payable installment so the cash-collection request has a schedule.
    if (_scheduleId.isEmpty) {
      final loanId = widget.extra['loan_id'] as String? ?? '';
      if (loanId.isNotEmpty) {
        _resolving = true;
        Future.microtask(_resolveSchedule);
      }
    }
  }

  @override
  void dispose() {
    _collectionSub?.close();
    super.dispose();
  }

  Future<void> _resolveSchedule() async {
    final loanId = widget.extra['loan_id'] as String? ?? '';
    if (loanId.isEmpty) return;
    try {
      await ref.read(lenderLoanProvider.notifier).loadLoanDetails(loanId);
      if (!mounted) return;
      final schedules =
          ref.read(lenderLoanProvider).selectedLoan?.schedules ?? [];
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
    } finally {
      if (mounted) setState(() => _resolving = false);
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
        title: const Text('Payment Already Pending'),
        content: const Text('You already have a pending payment for this installment. Please wait for it to be processed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  /// Shared positive modal para sa matagumpay (o malamang naipadala) na
  /// request — malinaw na confirmation imbes na error/tongue-twister text.
  ///
  /// AUTO-CLOSE pagkatapos ng 3 segundo (isang "Close" button lang; walang
  /// "View Collections" — nasa Payments tab pa rin naman ang collections).
  Future<void> _showSubmittedDialog({
    required String title,
    required String message,
  }) =>
      SuccessDialog.showAutoDismiss(
        context,
        title: title,
        message: message,
        buttonText: 'Close',
        duration: const Duration(seconds: 3),
      );

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

  Future<void> _requestCashCollection() async {
    if (_scheduleId.isEmpty) {
      AppLogger.w('[PaymentMethod] _requestCashCollection called with empty schedule_id extra=${widget.extra}');
      _showInfo('Missing installment information. Please return to Payment Schedule and tap Pay again.');
      return;
    }
    if (_hasPendingLocally()) {
      AppLogger.d('[PaymentMethod] _hasPendingLocally true for $_scheduleId — skipping server call');
      await _showPendingDialog();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cash on Delivery'),
        content: const Text(
          'Are you sure you want to pay with Cash on Delivery?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Bago ang final na COD request: device credential authentication
    // (fingerprint / Face ID, o device PIN/password fallback).
    final verified = await _authenticateForPayment();
    if (!verified || !mounted) return;

    AppLogger.d('[PaymentMethod] User confirmed rider collection schedule=$_scheduleId loan=${widget.extra['loan_id']} amount=$_amount');
    setState(() => _requesting = true);
    bool ok = false;
    try {
      ok = await ref
          .read(lenderPaymentProvider.notifier)
          .requestRiderCollection(loanScheduleId: _scheduleId, amount: _amount);
    } catch (e, st) {
      AppLogger.e('[PaymentMethod] requestRiderCollection threw', e, st);
      if (kDebugMode) debugPrint('[PaymentMethod] exception: $e');
      ok = false;
    }
    if (!mounted) return;
    setState(() => _requesting = false);

    // A failed client call does not prove the request was rejected: the server
    // may have created the assignment after we stopped waiting (timeout, 5xx,
    // slow staff push fan-out). Ask the server whether the request exists
    // before claiming it was not sent.
    if (!ok) {
      ok = await _requestExistsOnServer();
      if (ok) {
        AppLogger.i(
            '[PaymentMethod] request found on server despite client failure — treating as sent schedule=$_scheduleId');
      }
    }

    // Keep the schedule screen's pending chip in sync even before realtime.
    // Silent — hindi dapat mag-loading ang listahan matapos pindutin ang Yes.
    if (ok) {
      ref.read(lenderCollectionProvider.notifier).loadList(silent: true);
    }

    // Walang mounted check pagkatapos ng huling `await` (`_requestExistsOnServer`)
    // — kailangan ito bago gamitin muli ang `context` sa mga dialog sa ibaba.
    if (!mounted) return;

    if (ok) {
      AppLogger.i('[PaymentMethod] rider request OK schedule=$_scheduleId');
      await _showSubmittedDialog(
        title: 'Successfully Submitted',
        // Business process: ang pag-assign ng rider at paghahatid ng cash ay
        // inaasahang matapos sa loob ng 1–2 business days.
        message: 'Your Cash on Delivery request has been submitted. '
            'Our office will assign a rider and deliver the cash within '
            '1–2 business days. You will be notified once the cash is on '
            'the way.',
      );
    } else {
      final err = ref.read(lenderPaymentProvider).error;
      AppLogger.w('[PaymentMethod] rider request FAILED schedule=$_scheduleId error=$err');
      if (kDebugMode) debugPrint('[PaymentMethod] failure dialog error: $err');
      // A lost/timed-out response is NOT proof of failure — the request was
      // already re-checked against the server above. Huwag magpakita ng
      // nakalilitong "Request Timed Out" kapag walang tunay na error.
      final low = (err ?? '').toLowerCase();
      final inconclusive = err == null ||
          err.trim().isEmpty ||
          low.contains('timed out') ||
          low.contains('timeout') ||
          low.contains('unable to reach') ||
          low.contains('no internet') ||
          low.contains('server error') ||
          low.contains('internal server error') ||
          low.contains('an error occurred');
      if (inconclusive) {
        await _showSubmittedDialog(
          title: 'Submission Received',
          message: 'Your request was sent and is now being processed. '
              'It usually takes 1–2 business days before the rider delivers '
              'the cash. You will be notified once it is on the way.',
        );
        return;
      }
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
              ? 'You already have a pending payment for this installment. Please wait for it to be processed.'
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

  /// True kapag may pending collection request na sa server para sa installment
  /// na ito. Ginagamit kapag "failure" ang bumalik sa client pero posible na
  /// palang naipasok ng backend ang request (lost response / timeout). Kung
  /// meron, hindi na dapat sabihin ng app na "Request Not Sent".
  ///
  /// Ilang beses itong sinusubukan (may maliit na pagitan): kahit naipasok na
  /// agad ng server ang request, hindi ito agad lumalabas sa unang listahan
  /// kaya kung minsan may maling "Request Not Sent" na lumalabas.
  Future<bool> _requestExistsOnServer() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        // Silent — hindi dapat mag-loading/shimmer ang collection list habang
        // nagre-recheck pagkatapos ng "failure".
        await ref
            .read(lenderCollectionProvider.notifier)
            .loadList(silent: true);
        if (!mounted) return false;
        if (_hasPendingLocally()) return true;
      } catch (e) {
        AppLogger.w('[PaymentMethod] server re-check failed: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return false;
    }
    return false;
  }

  /// Device credential authentication bago ang Cash on Delivery request —
  /// fingerprint / Face ID / device PIN, at ang app-level MPIN kapag walang
  /// password ang phone. Success/failure lang ang natatanggap ng app — hindi
  /// nito binabasa ni ipinapadala ang device PIN/password.
  Future<bool> _authenticateForPayment() =>
      ref.read(submissionGuardProvider).confirm(
            context,
            reason: kSubmissionVerificationReason,
          );

  void _showInfo(String message) {
    context.showSnackBarAsToast(
        SnackBar(content: Text(message)));
  }

  /// Pay button sa baba — depende sa napiling radio. Ang rider request ay
  /// pumapasok bilang collection request na nakikita ni HM/employee.
  void _onPay() {
    if (_requesting) return;
    if (_selected == 'office') {
      if (_hasPendingLocally()) {
        _showPendingDialog();
        return;
      }
      context.push(RouteConstants.lenderOfficePayment, extra: {
        'loan_id': widget.extra['loan_id'],
        'schedule_id': _scheduleId,
        'amount': _amount,
        'due_date': _dueDate,
      });
      return;
    }
    _requestCashCollection();
  }

  @override
  Widget build(BuildContext context) {
    // Walang installment (naglo-load pa o walang nahanap) → disabled ang Pay
    // para hindi mag-toast ng "Missing installment information".
    final payDisabled =
        _requesting || _resolving || _scheduleId.isEmpty;
    return MobileScaffold(
      title: 'Payment Method',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                const Text('Pay this installment via Cash on Delivery:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 26),
                _MethodCard(
                  value: 'rider',
                  groupValue: _selected,
                  onSelect: _requesting
                      ? null
                      : (v) => setState(() => _selected = v),
                  icon: Icons.delivery_dining_outlined,
                  assetPath: 'assets/icons/paywithrider.jpg',
                  color: AppColors.riderGreen,
                  title: 'Cash on Delivery',
                  badge: null,
                ),
                // HIDDEN: "Office" option — Cash on Delivery lang ang
                // ipinapakita ngayon. Nasa code pa rin ang handler
                // (`_onPay` → `/lender/pay-office`) kung ibabalik ito.
                const SizedBox(height: 14),
                const _MethodCard(
                  value: 'gcash',
                  groupValue: 'rider',
                  onSelect: null,
                  icon: Icons.account_balance_wallet,
                  color: Color(0xFF007DFF),
                  title: 'GCash',
                  badge: null,
                  disabled: true,
                ),
                if (!_resolving && _scheduleId.isEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'No payable installment found. Please return to Payment Schedule and tap Pay again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          // Naka-pin sa baba ng mobile view — hindi na kailangang mag-scroll
          // para makita ang Pay button. Nakaangat sa TAAS ng floating bottom
          // nav.
          //
          // GAMIT DITO: `mobileBottomNavHeight` (hindi `mobileBottomNavInset`)
          // dahil ang `context` na ito ay ang context ng SCREEN — nasa LABAS
          // ito ng body ng MobileScaffold, kaya `MediaQuery.padding.bottom` ay
          // safe area lang (0 pa nga sa mga Android na walang home indicator).
          // Ang `mobileBottomNavHeight` ang nagdadagdag ng float gap + pill
          // height, kaya eksaktong nasa itaas ng pill ang button.
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              mobileBottomNavHeight(context) + 8,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: payDisabled ? null : _onPay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.lenderBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.lenderBlue.withValues(alpha: 0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: (_requesting || _resolving)
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _selected == 'office'
                            ? 'Pay via Office'
                            : 'Pay via Cash on Delivery',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final String value;
  final String groupValue;
  final ValueChanged<String>? onSelect;
  final IconData icon;
  final String? assetPath;
  final Color color;
  final String title;
  final String? badge;
  final bool disabled;

  const _MethodCard({
    required this.value,
    required this.groupValue,
    required this.onSelect,
    required this.icon,
    this.assetPath,
    required this.color,
    required this.title,
    required this.badge,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = disabled ? AppColors.textTertiary : color;
    final selected = !disabled && value == groupValue;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: disabled || onSelect == null ? null : () => onSelect!(value),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.lenderBlue : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              if (assetPath != null)
                SizedBox(
                  width: 46,
                  height: 46,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      assetPath!,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          color:
                              effectiveColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child:
                            Icon(icon, color: effectiveColor, size: 24),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: effectiveColor, size: 24),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Row(
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
              ),
              _RadioDot(selected: selected, disabled: disabled),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom radio dot — iwas sa deprecated Radio groupValue/onChanged API.
class _RadioDot extends StatelessWidget {
  final bool selected;
  final bool disabled;
  const _RadioDot({required this.selected, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    final color =
        disabled ? AppColors.textTertiary : AppColors.lenderBlue;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? color : AppColors.border,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
            )
          : null,
    );
  }
}