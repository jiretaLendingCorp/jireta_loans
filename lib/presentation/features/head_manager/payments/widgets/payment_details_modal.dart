// lib/presentation/features/head_manager/payments/widgets/payment_details_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/hm_payment_provider.dart';

final paymentDetailFutureProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) async {
  final ds = sl<PaymentRemoteDataSource>();
  try {
    final p = await ds.getPaymentDetail(id);
    return {
      'id': p.id,
      'status': p.status,
      'method': p.method,
      'amount': p.amount,
      // Ipinapasa ang DateTime mismo — `p.createdAt` ay Manila wall time na
      // (parseManila sa PaymentModel). Kapag ni-encode pa ito pabalik sa ISO
      // string na may `Z` at ni-parse ulit ng parseManila, made-doble ang +8h
      // (Sep 16 21:06 → Sep 17 05:06 AM).
      'created_at': p.createdAt,
      'reference_number': p.referenceNumber,
      'xendit_payment_id': p.xenditPaymentId,
      'notes': p.notes,
      'loan': p.loan,
      'recorded_by_user': p.recordedByUser,
    };
  } catch (_) {
    return null;
  }
});

/// Opens payment details as a modal — ginagamit ng View action sa Payments at
/// Collections tables imbes na full-page navigation.
///
/// Nanatili pa rin ang `/hm/payments/:id` route (deep link ng FCM
/// notification), at pareho silang gumagamit ng [HmPaymentDetailsContent]
/// para isang layout lang ang ina-update.
Future<void> showPaymentDetailsModal(
    BuildContext context, String paymentId) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      // Square corners ang modal — walang border radius.
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Payment Details',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepNavy)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close,
                        size: 20, color: AppColors.textSecondary),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(child: HmPaymentDetailsContent(paymentId: paymentId)),
          ],
        ),
      ),
    ),
  );
}

/// Body ng payment details — walang scaffold, kaya pwedeng gamitin sa modal at
/// sa `/hm/payments/:id` route. Kapag `null` ang [onBack], hindi na ipinapakita
/// ang back arrow + title row (may sariling header na ang modal).
class HmPaymentDetailsContent extends ConsumerStatefulWidget {
  final String paymentId;
  final VoidCallback? onBack;
  const HmPaymentDetailsContent(
      {super.key, required this.paymentId, this.onBack});

  @override
  ConsumerState<HmPaymentDetailsContent> createState() =>
      _HmPaymentDetailsContentState();
}

class _HmPaymentDetailsContentState
    extends ConsumerState<HmPaymentDetailsContent> {
  bool _reversing = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(paymentDetailFutureProvider(widget.paymentId));
    return async.when(
      loading: () => const Center(child: ShimmerLoader()),
      error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (d) => d == null
          ? const Center(child: Text('Payment not found'))
          : _buildBody(context, d),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> d) {
    final status = (d['status'] ?? '').toString();
    final method = (d['method'] ?? '').toString();
    final amount = (d['amount'] as num?)?.toDouble() ?? 0;
    final createdAt = parseManilaValue(d['created_at']);
    final loan = d['loan'] as Map<String, dynamic>?;
    final recordedByUser = d['recorded_by_user'] as Map<String, dynamic>?;
    final refNumber = d['reference_number']?.toString().trim() ?? '';
    // Kapag cash (office/rider) ang bayad, walang Xendit reference — dati
    // buong payment UUID ang ipinapakita sa "Reference #". Gumawa na lang ng
    // stable, readable reference mula sa payment id (pareho ng convention ng
    // lender receipt screen) para hindi nagmumukhang bug ang UUID.
    final displayRef =
        refNumber.isNotEmpty ? refNumber : _deriveReference(d['id']?.toString());
    final onBack = widget.onBack;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Back arrow + title (full page lang) ─────────────────────────
          if (onBack != null) ...[
            Row(
              children: [
                _BackArrow(onTap: onBack),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Payment Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.deepNavy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Hero card: amount, ref, status ──────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AMOUNT PAID',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  amount.toCurrency,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // `onDark: true` — ang hero card na ito ay `deepNavy`, kaya
                    // hindi mabasa ang status na walang sariling mapping
                    // (hal. "reversed") kapag semantic/gray ang label color.
                    StatusBadge(status: status, onDark: true),
                    // Ang method at date ay plain metadata text lang (may dot
                    // separator) — hindi pill/chip, para malinaw na hindi ito
                    // clickable at hindi mukhang button.
                    const _MetaDot(),
                    _MetaText(_methodLabel(method)),
                    if (createdAt != null) ...[
                      const _MetaDot(),
                      _MetaText(
                        DateFormat('MMM dd, yyyy • hh:mm a').format(createdAt),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Payment info ────────────────────────────────────────────────
          _InfoCard(
            title: 'Payment Information',
            rows: [
              _InfoRow('Amount', amount.toCurrency, valueBesideLabel: true),
              _InfoRow('Method', _methodLabel(method), valueBesideLabel: true),
              _InfoRow('Status', status.toUpperCase(), valueBesideLabel: true),
              _InfoRow('Reference #', displayRef.isEmpty ? '—' : displayRef,
                  valueBesideLabel: true),
              if (d['xendit_payment_id'] != null)
                _InfoRow('Xendit ID', d['xendit_payment_id'].toString(),
                    valueBesideLabel: true),
              if (d['notes'] != null && d['notes'].toString().isNotEmpty)
                _InfoRow('Notes', d['notes'].toString(),
                    valueBesideLabel: true),
              if (createdAt != null)
                _InfoRow('Date',
                    DateFormat('MMM dd, yyyy hh:mm a').format(createdAt),
                    valueBesideLabel: true),
            ],
          ),

          // ── Loan info ───────────────────────────────────────────────────
          if (loan != null) ...[
            const SizedBox(height: 16),
            _InfoCard(
              title: 'Loan Information',
              rows: [
                _InfoRow('Loan #', (loan['loan_number'] ?? '—').toString(),
                    valueBesideLabel: true),
                _InfoRow('Total Payable', _moneyLabel(loan['total_payable']),
                    valueBesideLabel: true),
                _InfoRow(
                    'Outstanding Balance',
                    _moneyLabel(loan['outstanding_balance']),
                    valueBesideLabel: true),
                _InfoRow('Status', _titleLabel(loan['status']),
                    valueBesideLabel: true),
              ],
            ),
          ],

          // ── Recorded by ─────────────────────────────────────────────────
          if (recordedByUser != null) ...[
            const SizedBox(height: 16),
            _InfoCard(
              title: 'Recorded By',
              rows: [
                _InfoRow(
                    'Name',
                    '${recordedByUser['first_name'] ?? ''} ${recordedByUser['last_name'] ?? ''}'
                        .trim(),
                    valueBesideLabel: true),
                _InfoRow('Role', _roleLabel(recordedByUser['role']),
                    valueBesideLabel: true),
              ],
            ),
          ],

          // ── Reverse action ──────────────────────────────────────────────
          if (status == 'verified') ...[
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    _reversing ? null : () => _reversePayment(context, d['id']),
                icon: _reversing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.error,
                        ),
                      )
                    : const Icon(Icons.undo_rounded, size: 18),
                label: Text(_reversing ? 'Reversing…' : 'Reverse Payment'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _reversePayment(BuildContext context, String? paymentId) async {
    if (paymentId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => const ConfirmationDialog(
        title: 'Reverse Payment',
        message:
            'Are you sure you want to reverse this payment? This action cannot be undone.',
        confirmLabel: 'Reverse',
        confirmColor: AppColors.error,
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _reversing = true);
    try {
      final notifier = ref.read(hmPaymentProvider.notifier);
      final ok = await notifier.reverse(
          paymentId: paymentId, reason: 'Manual reversal by Head Manager');
      if (!mounted) return;
      if (ok) {
        if (!context.mounted) return;
        showDialog(
            context: context,
            builder: (_) =>
                const SuccessDialog(message: 'Payment reversed successfully.'));
        ref.invalidate(paymentDetailFutureProvider(widget.paymentId));
      } else {
        if (!context.mounted) return;
        showDialog(
            context: context,
            builder: (_) =>
                const ErrorDialog(message: 'Failed to reverse payment.'));
      }
    } finally {
      if (mounted) setState(() => _reversing = false);
    }
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'gcash':
        return 'GCash';
      case 'office_cash':
      case 'cash':
        return 'Office Cash';
      case 'rider_collection':
        return 'Rider Collection';
      default:
        return method.isEmpty ? '—' : method;
    }
  }

  /// Stable na reference para sa mga bayad na walang Xendit reference
  /// (office cash / rider collection): `JR-<12 hex chars>` mula sa payment id.
  String _deriveReference(String? paymentId) {
    final compact = (paymentId ?? '').replaceAll('-', '').toUpperCase();
    if (compact.isEmpty) return '';
    return 'JR-${compact.length >= 12 ? compact.substring(0, 12) : compact}';
  }

  /// `null` ang derived financial fields kapag hindi available — mas malinaw
  /// ang '—' kaysa maling ₱0.00.
  String _moneyLabel(Object? value) =>
      value is num ? value.toDouble().toCurrency : '—';

  String _titleLabel(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '—';
    return raw
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// `role` comes back as the roles.name string (o { name } embed kapag iba
  /// ang source) — hindi na '—' ang "Recorded By → Role".
  String _roleLabel(Object? role) {
    final raw = role is Map ? (role['name'] ?? role['label'] ?? role['code']) : role;
    final value = raw?.toString().trim() ?? '';
    switch (value) {
      case 'head_manager':
        return 'Head Manager';
      case 'employee':
        return 'Employee';
      case 'rider':
        return 'Rider';
      case 'lender':
        return 'Lender';
      default:
        return _titleLabel(value);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Support widgets
// ─────────────────────────────────────────────────────────────────────────────

class _BackArrow extends StatelessWidget {
  final VoidCallback onTap;
  const _BackArrow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.arrow_back_rounded,
              size: 20, color: AppColors.deepNavy),
        ),
      ),
    );
  }
}

/// Plain metadata text sa loob ng dark hero card — walang pill background at
/// border, kaya hindi ito nagmumukhang button.
class _MetaText extends StatelessWidget {
  final String label;
  const _MetaText(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Colors.white70,
      ),
    );
  }
}

/// Maliit na dot separator sa pagitan ng status / method / date.
class _MetaDot extends StatelessWidget {
  const _MetaDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<_InfoRow> rows;
  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.deepNavy,
              ),
            ),
            const SizedBox(height: 14),
            ...rows.map((r) => r),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  /// `true` → katabi agad ng label ang value (fixed-width label column),
  /// hindi naka-push sa dulong kanan ng card. Default: right-aligned.
  final bool valueBesideLabel;

  const _InfoRow(this.label, this.value, {this.valueBesideLabel = false});

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 13,
    );
    const valueStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 13,
      color: AppColors.textPrimary,
    );

    if (valueBesideLabel) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fixed-width label column — sa tabi mismo nito nakaupo ang value.
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: labelStyle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value.isEmpty ? '—' : value,
                style: valueStyle,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: labelStyle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}
