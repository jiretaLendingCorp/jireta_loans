// lib/presentation/shared/widgets/rider_quota_progress.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Kulay ng quota progress — visual aid lang. Ang "achieved" ay galing sa
/// server (confirmed >= target), hindi sa clamped na porsyento.
Color riderQuotaProgressColor(double? percent, {bool achieved = false}) {
  if (achieved) return AppColors.success;
  if (percent == null) return AppColors.textTertiary;
  if (percent >= 80) return AppColors.success;
  if (percent >= 50) return AppColors.warning;
  return AppColors.statusRejected;
}

/// Progress bar na naka-cap sa 100% ang haba, pero ang TEXT ay ang totoong
/// porsyento (hal. 125.0% kapag lumampas sa target). Hindi binabago ang
/// `confirmed` na halaga — display lang ang cap.
class RiderQuotaProgress extends StatelessWidget {
  final double? percent;
  final bool achieved;
  final double barHeight;
  final bool showLabel;

  const RiderQuotaProgress({
    super.key,
    required this.percent,
    this.achieved = false,
    this.barHeight = 5,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final value = percent;
    final color = riderQuotaProgressColor(value, achieved: achieved);
    final clamped = ((value ?? 0) / 100).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel)
          Text(
            value == null ? 'No target' : '${value.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        if (showLabel) const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: barHeight,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
