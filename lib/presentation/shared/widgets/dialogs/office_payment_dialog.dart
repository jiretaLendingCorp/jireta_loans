// lib/presentation/shared/widgets/dialogs/office_payment_dialog.dart
import 'package:flutter/material.dart';

// Ang theme-aware getters (cTextPrimary, cBorder, ...) ay nasa app_colors.dart.
import '../../../../core/theme/app_colors.dart';

/// Confirm + editable amount para sa walk-in (office) payment.
///
/// Ibinabalik ang halagang naitala, o `null` kapag kinansela. Maaaring baguhin
/// ang halaga para sa partial o advance na bayad — ang default ay ang
/// natitirang balanse ng installment.
///
/// Isang lugar lang ang dialog na ito para pareho ang UX sa lahat ng
/// nagre-record ng office payment: Collections → All Pending Payment (office
/// requests) at ang Payment Schedule ng loan.
///
/// Square ang lahat ng sulok (walang border radius) — tugma sa flat na card /
/// panel style ng app sa halip na ang rounded na Material default dialog.
Future<double?> showOfficePaymentDialog(
  BuildContext context, {
  required String lenderName,
  required String loanNumber,
  required double amount,
  String? installmentLabel,
}) {
  final ctrl = TextEditingController(text: amount.toStringAsFixed(2));

  void submit() {
    final v = double.tryParse(ctrl.text.replaceAll(',', '').trim());
    if (v == null || v <= 0) return;
    Navigator.of(context).pop(v);
  }

  final future = showDialog<double>(
    context: context,
    builder: (ctx) => Dialog(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: icon + title, kapareho ng ibang dialogs ng app.
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    color: AppColors.success.withValues(alpha: 0.1),
                    child: const Icon(Icons.payments_outlined,
                        color: AppColors.success, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Paid in Office',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ctx.cTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Sino at aling installment ang binabayaran.
              Text(
                '${lenderName.isEmpty ? 'This lender' : lenderName}'
                '${loanNumber.isEmpty ? '' : ' • $loanNumber'}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ctx.cTextPrimary),
              ),
              if (installmentLabel != null && installmentLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(installmentLabel,
                    style: TextStyle(
                        fontSize: 12, color: ctx.cTextSecondary)),
              ],
              const SizedBox(height: 16),

              // Square ang field — walang rounded corners.
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ctx.cTextPrimary),
                decoration: InputDecoration(
                  labelText: 'Amount (₱)',
                  isDense: true,
                  labelStyle:
                      TextStyle(fontSize: 13, color: ctx.cTextSecondary),
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: ctx.cBorder),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide:
                        BorderSide(color: AppColors.success, width: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                        foregroundColor: ctx.cTextSecondary),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                    onPressed: submit,
                    child: const Text('Mark as Paid',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // I-dispose ang controller pagkasarado ng dialog (success man o cancel).
  return future.whenComplete(ctrl.dispose);
}
