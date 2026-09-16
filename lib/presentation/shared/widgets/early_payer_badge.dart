// lib/presentation/shared/widgets/early_payer_badge.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Badge para sa lender na "early payer": LAHAT ng verified na installment
/// payment niya ay binayaran BAGO o sa exactong due date (base sa loan term na
/// kinuha niya). Makikita ito ng Head Manager at Employee sa lender list at
/// lender details.
class EarlyPayerBadge extends StatelessWidget {
  /// Mas maliit na bersyon para sa mga table row.
  final bool small;

  /// Ilang araw na nauna ang pinakamaagang bayad (opsyonal na detalye).
  final int? daysEarly;

  const EarlyPayerBadge({super.key, this.small = false, this.daysEarly});

  @override
  Widget build(BuildContext context) {
    final ahead = daysEarly ?? 0;
    final label = ahead > 0 ? 'Early Payer · ${ahead}d ahead' : 'Early Payer';
    // Plain text lang — hindi button, kaya walang background/border/pill.
    // Ang bolt icon + berdeng bold na teksto ang nagdadala ng kahulugan.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bolt_rounded,
            size: small ? 12 : 14, color: AppColors.success),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: small ? 10 : 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.success,
          ),
        ),
      ],
    );
  }
}
