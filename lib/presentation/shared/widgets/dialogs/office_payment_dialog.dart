// lib/presentation/shared/widgets/dialogs/office_payment_dialog.dart
import 'package:flutter/material.dart';

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
Future<double?> showOfficePaymentDialog(
  BuildContext context, {
  required String lenderName,
  required String loanNumber,
  required double amount,
  String? installmentLabel,
}) {
  final ctrl = TextEditingController(text: amount.toStringAsFixed(2));
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Paid in Office'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${lenderName.isEmpty ? 'This lender' : lenderName}'
            '${loanNumber.isEmpty ? '' : ' • $loanNumber'}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          if (installmentLabel != null && installmentLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              installmentLabel,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Kumpirmahin na nabayaran na sa office ang installment na ito. '
            'Maaaring baguhin ang halaga para sa partial o advance na bayad.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount (₱)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final v = double.tryParse(ctrl.text.replaceAll(',', '').trim());
            if (v == null || v <= 0) return;
            Navigator.pop(ctx, v);
          },
          child: const Text('Mark as Paid'),
        ),
      ],
    ),
  );
}
