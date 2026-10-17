// lib/presentation/features/lender/payments/screens/lender_pay_via_gcash_screen.dart
import 'dart:async';

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

class LenderPayViaGcashScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> extra;
  const LenderPayViaGcashScreen({super.key, required this.extra});

  @override
  ConsumerState<LenderPayViaGcashScreen> createState() => _State();
}

class _State extends ConsumerState<LenderPayViaGcashScreen>
    with WidgetsBindingObserver {
  String? _paymentUrl;

  /// Ang `payment_id` ng invoice — kokonfirmahin ito sa Xendit pagbalik mula sa
  /// checkout, para hindi manatiling `pending` ang bayad kapag hindi umabot ang
  /// webhook callback.
  String? _paymentId;
  bool _checkingPayment = false;
  bool _paymentVerified = false;

  /// Paalala lang kapag hindi pa nakumpirma ng Xendit — HIWALAY sa `_error`,
  /// para hindi lumabas ang "Retry" (na gumagawa ng bagong invoice).
  String? _checkMessage;
  bool _isGenerating = false;
  bool _paymentInitiated = false;

  /// Hinarang ang pagbukas ng checkout (popup blocker sa web, o walang app na
  /// makakabukas ng URL). Hindi ito error: ipinapakita ang link sa ibaba at
  /// may button na pwedeng pindutin.
  bool _launchFailed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _paymentId = widget.extra['payment_id'] as String?;
    // MANWAL NA LANDAS: kapag ang `payment_url` ay ipinasa na (nagawa na ang
    // invoice sa Payment Method screen pero hinarang ang pagbukas), huwag nang
    // mag-generate ng panibago — doble ang invoice at `payments` row kung ganoon.
    final provided = (widget.extra['payment_url'] as String?)?.trim();
    if (provided != null && provided.isNotEmpty) {
      _paymentUrl = provided;
      // Ipakita agad ang manwal na link (ito ang dahilan ng pagpunta dito).
      _launchFailed = true;
      return;
    }
    Future.microtask(_generateLink);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Bumalik ang lender mula sa Xendit checkout — kumpirmahin agad ang bayad.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _paymentId != null &&
        !_paymentVerified) {
      unawaited(_checkPayment(quiet: true));
    }
  }

  Future<void> _checkPayment({bool quiet = false}) async {
    final paymentId = _paymentId;
    if (paymentId == null || _checkingPayment) return;
    setState(() => _checkingPayment = true);
    final verified = await ref
        .read(lenderPaymentProvider.notifier)
        .syncXenditPaymentStatus(paymentId);
    if (!mounted) return;
    setState(() {
      _checkingPayment = false;
      _paymentVerified = verified;
    });
    if (!verified && !quiet) {
      setState(() => _checkMessage =
          'Xendit has not confirmed this payment yet. Please wait a few '
          'seconds and check again.');
    } else if (verified) {
      setState(() => _checkMessage = null);
    }
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
    // Ang provider ay naglalagay ng SANITIZED na dahilan mula sa Edge Function
    // (hal. "Loan is not active", "Installment already paid", o ang rate-limit
    // na mensahe) — iyon ang ipapakita imbes na generic na "Failed...", para
    // malinaw sa lender kung bakit hindi nabuo ang GCash link.
    final providerError = ref.read(lenderPaymentProvider).error?.trim();
    final failed = url == null || url.isEmpty;
    setState(() {
      _isGenerating = false;
      _paymentUrl = url;
      _paymentId ??= ref.read(lenderPaymentProvider).lastXenditPaymentId;
      _launchFailed = false;
      _error = failed
          ? ((providerError != null && providerError.isNotEmpty)
              ? providerError
              : 'Failed to generate payment link. Please try again.')
          : null;
    });
    if (!failed) {
      // DERETSO SA CHECKOUT: buksan agad ang hosted Xendit checkout page
      // (`invoice_url`) pagkatapos itong mabuo — hindi na kailangan ng
      // pangalawang tap. Kapag hinarang ito ng browser (popup blocker sa web
      // dahil hindi na kasama ang orihinal na tap) o walang app na
      // makakabukas, hindi ito tinatrato na error: nasa ibaba ang link at ang
      // button.
      await _openCheckout(auto: true);
    }
  }

  /// Bubuksan ang Xendit checkout (`invoice_url`). [auto] = ang unang
  /// pagsubok pagkatapos ma-generate ang link, kaya hindi ito nagpapakita ng
  /// error banner kahit harangin ng browser — ang fallback UI ang sapat.
  Future<void> _openCheckout({bool auto = false}) async {
    final url = _paymentUrl;
    if (url == null || url.isEmpty) return;
    var launched = false;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Walang platform handler (hal. sa widget tests) — fallback UI na lang.
      launched = false;
    }
    if (!mounted) return;
    setState(() {
      if (launched) {
        _paymentInitiated = true;
        _launchFailed = false;
        _error = null;
      } else {
        _launchFailed = true;
        _error = auto
            ? null
            : 'Could not open the Xendit checkout. Please use the secure link below.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      title: 'Pay via GCash',
      accentColor: AppColors.lenderBlue,
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
              'You will be redirected to the secure Xendit checkout page to complete your payment.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 36),
            if (_isGenerating)
              const Column(
                children: [
                  CircularProgressIndicator(color: AppColors.lenderBlue),
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
                      color: AppColors.lenderBlue),
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
                  // Maikli ang label: ang `AppButton` ay `Row` na hindi
                  // flexible ang text, kaya ang mahabang label ay nag-o-overflow
                  // sa makitid na phone. Nasa title at description na ang
                  // "Xendit checkout", kaya sapat na ang "Open Checkout".
                  AppButton(
                    label:
                        _paymentInitiated ? 'Open Checkout Again' : 'Open Checkout',
                    onPressed: _openCheckout,
                    color: const Color(0xFF007DFF),
                    icon: Icons.open_in_new,
                  ),
                  if (_paymentId != null) ...[
                    const SizedBox(height: 18),
                    if (_paymentVerified)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: AppColors.success),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'GCash payment confirmed. Your balance has been updated.',
                                style: TextStyle(
                                    color: AppColors.success, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: [
                          TextButton(
                            onPressed:
                                _checkingPayment ? null : () => _checkPayment(),
                            child: Text(_checkingPayment
                                ? 'Checking…'
                                : 'Already paid? Check payment status'),
                          ),
                          if (_checkMessage != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _checkMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                  ],
                  if (_launchFailed) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'If the checkout did not open, use this secure link:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _paymentUrl ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textPrimary),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
