// lib/presentation/shared/widgets/app_chip.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class AppChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color? bgColor;
  final IconData? icon;
  final double fontSize;

  const AppChip({
    super.key,
    required this.label,
    required this.color,
    this.bgColor,
    this.icon,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

Color statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'active':
    case 'verified':
    case 'completed':
    case 'approved':
    case 'accepted':
      return AppColors.statusActive;
    case 'pending':
    case 'submitted':
    case 'under_review':
    case 'ci_required':
    case 'ci_assigned':
    case 'ci_completed':
      return AppColors.statusPending;
    case 'rejected':
    case 'declined':
    case 'failed':
    case 'overdue':
      return AppColors.statusRejected;
    case 'cancelled':
    case 'suspended':
    case 'archived':
      return AppColors.textTertiary;
    case 'blacklisted':
      return AppColors.statusRejected;
    case 'whitelisted':
      return AppColors.statusActive;
    default:
      return AppColors.textSecondary;
  }
}

String statusLabel(String status) {
  return status
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
      .join(' ');
}
