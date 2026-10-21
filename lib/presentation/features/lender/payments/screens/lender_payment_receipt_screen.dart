// lib/presentation/features/lender/payments/screens/lender_payment_receipt_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../shared/utils/file_downloader.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/lender_payment_provider.dart';
import '../utils/payment_receipt_pdf.dart';

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
    // Desktop: makitid at naka-center ang receipt — hindi nakaunat ang card sa
    // buong browser width. Mobile: buong lapad pa rin (walang binago).
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    final maxContentWidth = isDesktop ? 720.0 : double.infinity;

    return MobileScaffold(
      title: 'Payment Receipt',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: async.when(
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
                    onPressed: () =>
                        ref.invalidate(_receiptProvider(paymentId)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.lenderBlue),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (data) => _buildReceipt(context, data),
          ),
        ),
      ),
    );
  }

  Widget _buildReceipt(BuildContext context, Map<String, dynamic> data) {
    final receiptUrl = data['receipt_url'] as String?;
    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final method = data['payment_method'] as String? ?? '';
    final status = data['status'] as String? ?? '';
    final refNum = data['reference_number'] as String? ?? '';
    // `created_at` ay DateTime na (Manila wall time) mula sa provider — kung
    // raw string naman, doon lang dinadaan ang +8h shift.
    final paidAt = parseManilaValue(data['created_at']);
    final loanNum = data['loan_number'] as String? ?? '';
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          16, isDesktop ? 32 : 16, 16, isDesktop ? 48 : 100),
      child: Column(
        children: [
          _ReceiptCard(
            amount: amount,
            method: method,
            status: status,
            refNum: refNum,
            paidAt: paidAt,
            loanNum: loanNum,
            data: data,
            receiptUrl: receiptUrl,
          ),
          const SizedBox(height: 22),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 14, color: AppColors.textTertiary),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'This receipt is an official record of your payment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Download (at Share kapag may hosted URL) ng resibo — nasa LOOB ng receipt
/// card, sa ilalim ng "Date & Time", at TEXT LINK lang (walang button/box).
///
/// Dating `receipt_url`-only ang mga button sa ilalim ng card, kaya kapag
/// `null` (madalas sa GCash/Xendit payments) ay wala talagang paraan para
/// i-download ang resibo.
class _ReceiptActions extends StatefulWidget {
  final Map<String, dynamic> data;
  final String? receiptUrl;

  const _ReceiptActions({
    required this.data,
    required this.receiptUrl,
  });

  @override
  State<_ReceiptActions> createState() => _ReceiptActionsState();
}

class _ReceiptActionsState extends State<_ReceiptActions> {
  bool _downloading = false;

  Future<void> _downloadReceipt() async {
    final url = widget.receiptUrl;
    if (url != null) {
      await _openWeb(url, external: true);
      return;
    }
    setState(() => _downloading = true);
    try {
      final bytes = await buildPaymentReceiptPdf(widget.data);
      await saveFile(bytes, paymentReceiptFileName(widget.data));
      if (!mounted) return;
      context.showSuccessToast('Receipt downloaded');
    } catch (_) {
      if (!mounted) return;
      context.showErrorToast('Unable to download the receipt');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openWeb(String url, {required bool external}) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: external
              ? LaunchMode.externalApplication
              : LaunchMode.platformDefault,
        );
      }
    } catch (_) {
      if (!mounted) return;
      context.showErrorToast('Unable to open the receipt');
    }
  }

  @override
  Widget build(BuildContext context) {
    final receiptUrl = widget.receiptUrl;
    // Naka-TAPAT sa ibaba ng "Date & Time": kaparehong kaliwang gilid ng
    // label ng detalye, at TEXT LINK lang (walang button/box).
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ReceiptLink(
            label: 'Download Receipt',
            icon: Icons.download_rounded,
            loading: _downloading,
            onTap: _downloadReceipt,
          ),
          if (receiptUrl != null) ...[
            const SizedBox(width: 14),
            Container(width: 1, height: 12, color: AppColors.border),
            const SizedBox(width: 14),
            _ReceiptLink(
              label: 'Share Receipt',
              icon: Icons.share_outlined,
              onTap: () => _openWeb(receiptUrl, external: false),
            ),
          ],
        ],
      ),
    );
  }
}

/// Text link lang — walang border, background, o padding ng button.
class _ReceiptLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;

  const _ReceiptLink({
    required this.label,
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: AppColors.lenderBlue,
                ),
              )
            else
              Icon(icon, size: 14, color: AppColors.lenderBlue),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.lenderBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Receipt card — itim-na-navy na seal sa itaas, malinaw na amount block,
/// dashed na hati, at naka-icon na detalye sa ibaba. Walay header gradient na
/// dating kalahati lang ng card ang may kulay.
class _ReceiptCard extends StatelessWidget {
  final double amount;
  final String method, status, refNum, loanNum;
  final DateTime? paidAt;
  final Map<String, dynamic> data;
  final String? receiptUrl;

  const _ReceiptCard(
      {required this.amount,
      required this.data,
      required this.receiptUrl,
      required this.method,
      required this.status,
      required this.refNum,
      required this.loanNum,
      this.paidAt});

  bool get _isPaid => status.toLowerCase() == 'verified';

  String get _methodLabel {
    switch (method) {
      case 'gcash':
      case 'gcash_xendit':
        return 'GCash';
      case 'office_cash':
      case 'cash':
        return 'Office';
      case 'rider_collection':
        return 'Rider Collection';
      default:
        return method.replaceAll('_', ' ');
    }
  }

  IconData get _methodIcon {
    if (method.contains('gcash')) return Icons.phone_android_rounded;
    if (method == 'office_cash' || method == 'cash') {
      return Icons.storefront_rounded;
    }
    if (method == 'rider_collection') return Icons.delivery_dining_rounded;
    return Icons.account_balance_wallet_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          // Manipis na gold strip — premium accent, hindi kalahating card na
          // gradient.
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.gold, AppColors.goldLight],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.lenderBlue, AppColors.lenderBlueLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.lenderBlue.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PAYMENT RECEIPT',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isPaid ? 'Payment Successful' : 'Payment Record',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(status: status),
              ],
            ),
          ),
          // Amount block — walang kahon; nakalutang lang sa puting card para
          // malinis at parang totoong resibo.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 24, 0),
            child: Column(
              children: [
                Text(
                  _isPaid ? 'AMOUNT PAID' : 'AMOUNT',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    amount.toCurrency,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.2,
                      color: AppColors.deepNavy,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // GCash / method — plain label lang, walang chip/box.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // GCash: brand asset mula sa `assets/images/gcash.png`.
                    if (method.contains('gcash'))
                      Image.asset(
                        'assets/images/gcash.png',
                        width: 16,
                        height: 16,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => Icon(_methodIcon,
                            size: 14, color: AppColors.textSecondary),
                      )
                    else
                      Icon(_methodIcon,
                          size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      _methodLabel,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _DashedDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Loan Number',
                  value: loanNum.isNotEmpty ? loanNum : '-',
                ),
                _DetailRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Payment Method',
                  value: _methodLabel,
                ),
                _DetailRow(
                  icon: Icons.pin_outlined,
                  label: 'Reference No.',
                  value: refNum.isNotEmpty ? refNum : '—',
                  mono: true,
                ),
                if (paidAt != null)
                  _DetailRow(
                    icon: Icons.event_outlined,
                    label: 'Date & Time',
                    value: paidAt!.formattedWithTime,
                    last: true,
                  ),
                // Download (text link) na naka-TAPAT sa ibaba ng "Date &
                // Time" — parehong kaliwang gilid, sa LOOB ng receipt card.
                _ReceiptActions(data: data, receiptUrl: receiptUrl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Semantic na status label ng bayad (`verified` → "Paid") — plain text, hindi
/// mukhang button: walang box, border, o background.
class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final low = status.toLowerCase();
    final color = low == 'verified'
        ? AppColors.success
        : low == 'pending'
            ? AppColors.warning
            : low == 'reversed' || low == 'failed'
                ? AppColors.error
                : AppColors.textSecondary;
    // Plain na label — HINDI pill/button: walang background, border, o padding.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          low == 'verified' ? Icons.check_circle_rounded : Icons.circle,
          size: low == 'verified' ? 13 : 7,
          color: color,
        ),
        const SizedBox(width: 5),
        StatusBadge(
          status: status,
          labelOverride: paymentStatusLabel(status),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final bool mono;
  final bool last;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: mono ? 12.5 : 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: mono ? 0.3 : 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!last) const Divider(height: 1, color: AppColors.divider),
      ],
    );
  }
}

/// Dashed na panghati — "resibo" feel. Simpleng dashes lang, walang image.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const dash = 6.0;
      const gap = 5.0;
      final count = (constraints.maxWidth / (dash + gap)).floor();
      return Row(
        children: List.generate(
          count,
          (_) => Container(
            width: dash,
            height: 1,
            margin: const EdgeInsets.only(right: gap),
            color: AppColors.border,
          ),
        ),
      );
    });
  }
}
