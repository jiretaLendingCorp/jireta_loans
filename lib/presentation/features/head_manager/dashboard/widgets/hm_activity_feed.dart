// lib/presentation/features/head_manager/dashboard/widgets/hm_activity_feed.dart
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/date_extensions.dart';

class ActivityEvent {
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final String type;
  final IconData? icon;

  const ActivityEvent({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.type,
    this.icon,
  });
}

class HmActivityFeed extends StatelessWidget {
  final List<ActivityEvent> events;
  final bool isLoading;

  const HmActivityFeed(
      {super.key, required this.events, this.isLoading = false});

  IconData _iconForType(String type) {
    switch (type) {
      case 'loan_applied':
        return Icons.description_outlined;
      case 'loan_approved':
        return Icons.check_circle_outline;
      case 'loan_rejected':
        return Icons.cancel_outlined;
      case 'account_upgrade_submitted':
        return Icons.person_add_outlined;
      case 'payment':
        return Icons.payments_outlined;
      case 'collection':
        return Icons.account_balance_wallet_outlined;
      case 'user_created':
        return Icons.person_outlined;
      case 'disbursement':
        return Icons.send_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'loan_approved':
        return AppColors.success;
      case 'loan_rejected':
        return AppColors.error;
      case 'payment':
        return AppColors.riderGreen;
      case 'collection':
        return AppColors.info;
      case 'account_upgrade_submitted':
        return AppColors.lenderBlue;
      case 'disbursement':
        return AppColors.gold;
      default:
        return AppColors.deepNavy;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.timeline, size: 18, color: AppColors.deepNavy),
                const SizedBox(width: 8),
                const Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('Live',
                    style: TextStyle(fontSize: 11, color: AppColors.success)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('No recent activity',
                    style: TextStyle(color: AppColors.textTertiary)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length > 10 ? 10 : events.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.divider),
              itemBuilder: (_, i) {
                final e = events[i];
                final color = _colorForType(e.type);
                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      e.icon ?? _iconForType(e.type),
                      size: 18,
                      color: color,
                    ),
                  ),
                  title: Text(
                    e.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    e.subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: Text(
                    e.timestamp.timeAgo,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
