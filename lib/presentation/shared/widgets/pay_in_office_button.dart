// lib/presentation/shared/widgets/pay_in_office_button.dart
import 'package:flutter/material.dart';

import 'package:jireta_loans/core/extensions/context_extensions.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/helpers.dart';
import '../../../data/datasources/remote/payment_remote_datasource.dart';
import 'dialogs/office_payment_dialog.dart';

/// Natitirang balanse ng isang installment: `amount_due` minus lahat ng
/// verified payments dito (`v_loan_schedules.amount_paid`).
double scheduleOutstanding(Map<String, dynamic> s) {
  final due = (s['amount_due'] as num?)?.toDouble() ?? 0;
  final paid = (s['amount_paid'] as num?)?.toDouble() ?? 0;
  return due - paid;
}

/// Hindi pa bayad at may natitira pang halaga — ito lang ang pwedeng i-record
/// bilang walk-in (office) payment. Ang `paid` na row ay wala nang babayaran.
bool isPayableScheduleRow(Map<String, dynamic> s) {
  final st = (s['status'] as String? ?? '').toLowerCase();
  return const {'pending', 'partial', 'overdue'}.contains(st) &&
      scheduleOutstanding(s) > 0;
}

/// Bayad na ang installment (o wala nang natitirang halaga) — kaya walang
/// dapat ipakitang Action dito, kahit dash.
///
/// Ito ang basehan ng empty Action cell sa Payment Schedule table: hindi na
/// dapat lumabas ang "—" kapag bayad na.
bool isSettledScheduleRow(Map<String, dynamic> s) {
  final st = (s['status'] as String? ?? '').toLowerCase();
  if (st == 'paid' || st == 'completed') return true;
  // Fully-paid na pero hindi pa na-update ang status (hal. huling partial na
  // eksaktong tumapat sa amount_due). Kapag wala ang `amount_paid` sa payload,
  // amount_due pa rin ang lumalabas dito, kaya hindi ito nagma-mark ng row na
  // hindi pa bayad.
  return scheduleOutstanding(s) <= 0;
}

/// Walk-in (office) payment action para sa isang installment.
///
/// BUSINESS RULE: verified na `office_cash` payment ang nililikha nito sa
/// `payments-manage?fn=record-office` — kaya
///   • BUMABABA ang outstanding balance ng loan (verified payment ang bawas),
///   • nagiging bayad na ang installment (`v_loan_schedules` → `paid`),
///   • makikita ng lender na nakabayad na siya, naka-record bilang
///     "Paid in Office", at nabibigyan siya ng notification.
///
/// Ang `onRecorded` ang nagpapa-refresh ng screen (schedule + balance).
class PayInOfficeButton extends StatefulWidget {
  final String loanId;
  final String scheduleId;

  /// Natitirang balanse ng installment — ito ang default na halaga sa dialog.
  final double amount;
  final String lenderName;
  final String loanNumber;

  /// Hal. "Installment #3" — ipinapakita sa dialog para malinaw kung alin.
  final String? installmentLabel;

  /// Tinatawag pagkatapos ng matagumpay na record.
  final Future<void> Function()? onRecorded;

  const PayInOfficeButton({
    super.key,
    required this.loanId,
    required this.scheduleId,
    required this.amount,
    this.lenderName = '',
    this.loanNumber = '',
    this.installmentLabel,
    this.onRecorded,
  });

  @override
  State<PayInOfficeButton> createState() => _PayInOfficeButtonState();
}

class _PayInOfficeButtonState extends State<PayInOfficeButton> {
  bool _busy = false;

  Future<void> _record() async {
    if (_busy) return;
    if (widget.loanId.isEmpty ||
        widget.scheduleId.isEmpty ||
        widget.amount <= 0) {
      context.showErrorToast(
          'Missing installment info. Please refresh and try again.');
      return;
    }

    final amount = await showOfficePaymentDialog(
      context,
      lenderName: widget.lenderName,
      loanNumber: widget.loanNumber,
      amount: widget.amount,
      installmentLabel: widget.installmentLabel,
    );
    if (amount == null || amount <= 0 || !mounted) return;

    setState(() => _busy = true);
    String? error;
    var ok = false;
    try {
      // Isang idempotency key lang: hindi madodoble ang record kapag
      // na-double tap o naulit ang request.
      await sl<PaymentRemoteDataSource>().recordOfficePayment(
        loanId: widget.loanId,
        loanScheduleId: widget.scheduleId,
        amount: amount,
        notes: 'Paid in office',
        idempotencyKey: AppHelpers.generateIdempotencyKey(),
      );
      ok = true;
    } catch (e) {
      error = ErrorHandler.handle(e).message;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    // Ang toast ay dapat LUMABAS AGAD pagkatapos huminto ang loading. Dati
    // inaantay pa ang `onRecorded()` (network refresh) bago ang toast — kaya
    // "tapos na ang loading" pero delayed pa ang "Paid in office" na mensahe.
    if (ok) {
      context.showToast(
          'Paid in office — ₱${amount.toStringAsFixed(2)} recorded');
    } else {
      context.showErrorToast(error ?? 'Failed to record office payment');
    }

    // Refresh — best effort lang at PAGKATAPOS ng toast: hindi ito dapat
    // mag-report ng failure o makapagpadelay ng success message kung
    // matagumpay nang naitala ang bayad.
    try {
      await widget.onRecorded?.call();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _busy ? null : _record,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.success)),
        // Ang Action cell ng Payment Schedule Table ay may TIGHT width
        // constraint (IntrinsicColumnWidth). Kapag bare `SizedBox` lang ang
        // nasa ilalim nito, na-e-enforce pabalik ang lapad ng buong column sa
        // spinner — kaya naging WIDE/patag ang loading. Ang `Row` ay nagbibigay
        // ng natural (loose) size sa mga anak, kaya bilog pa rin ang spinner at
        // pareho pa rin ang lapad ng button (hindi tumatalon ang column).
        child: _busy
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.success),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Pay in Office',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success),
                  ),
                ],
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront_rounded,
                      size: 14, color: AppColors.success),
                  SizedBox(width: 4),
                  Text(
                    'Pay in Office',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success),
                  ),
                ],
              ),
      ),
    );
  }
}
