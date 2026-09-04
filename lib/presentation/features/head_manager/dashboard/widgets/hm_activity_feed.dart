// lib/presentation/features/head_manager/dashboard/widgets/hm_activity_feed.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../data/datasources/remote/audit_remote_datasource.dart';
import '../../audit/audit_action_catalog.dart';

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

/// Latest audit entries mapped into feed events for the dashboard.
final hmRecentActivityProvider =
    FutureProvider<List<ActivityEvent>>((ref) async {
  final res = await sl<AuditRemoteDataSource>().getLogs(limit: 10);
  final items = (res['data'] as List?) ?? [];
  return items.map((raw) {
    final log = raw as Map<String, dynamic>;
    final action = log['action'] as String? ?? '';
    final user = log['performed_by_user'];
    final name = user is Map<String, dynamic>
        ? '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim()
        : '';
    final performer = name.isEmpty
        ? (log['performed_by'] == null ? 'System' : 'Staff')
        : name;
    final table = (log['table_name'] as String? ?? '').replaceAll('_', ' ');
    final label = AuditActionCatalog.label(action);
    return ActivityEvent(
      title: label.isEmpty ? 'Action' : label,
      subtitle: performer + (table.isEmpty ? '' : ' • $table'),
      timestamp:
          DateTime.tryParse(log['created_at']?.toString() ?? '') ??
              DateTime.now(),
      type: action,
    );
  }).toList();
});

class HmActivityFeed extends StatelessWidget {
  final List<ActivityEvent> events;
  final bool isLoading;

  const HmActivityFeed(
      {super.key, required this.events, this.isLoading = false});

  IconData _iconForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('approve')) return Icons.check_circle_outline;
    if (t.contains('reject') ||
        t.contains('decline') ||
        t.contains('cancel')) {
      return Icons.cancel_outlined;
    }
    if (t.contains('disburse')) return Icons.send_outlined;
    if (t.contains('payment') ||
        t.contains('collect') ||
        t.contains('xendit')) {
      return Icons.payments_outlined;
    }
    if (t.contains('penalty')) return Icons.gavel_rounded;
    if (t.contains('create') || t.contains('registered')) {
      return Icons.person_add_outlined;
    }
    if (t.contains('ci_')) return Icons.search_rounded;
    if (t.contains('upgrade')) return Icons.verified_user_outlined;
    if (t.contains('password')) return Icons.lock_reset_rounded;
    if (t.contains('archive')) return Icons.person_off_outlined;
    if (t.contains('report') || t.contains('export')) {
      return Icons.assessment_outlined;
    }
    return Icons.info_outline;
  }

  Color _colorForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('approve')) return AppColors.success;
    if (t.contains('reject') ||
        t.contains('decline') ||
        t.contains('cancel') ||
        t.contains('archive')) {
      return AppColors.error;
    }
    if (t.contains('penalty')) return AppColors.warning;
    if (t.contains('payment') ||
        t.contains('collect') ||
        t.contains('xendit')) {
      return AppColors.riderGreen;
    }
    if (t.contains('disburse')) return AppColors.goldDark;
    if (t.contains('create') ||
        t.contains('registered') ||
        t.contains('upgrade') ||
        t.contains('ci_')) {
      return AppColors.lenderBlue;
    }
    if (t.contains('password') || t.contains('reset')) return AppColors.info;
    if (t.contains('report') || t.contains('export')) {
      return AppColors.deepNavy;
    }
    return AppColors.deepNavy;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grey header strip (gaya ng loan details cards)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF5C6370),
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timeline_rounded,
                    size: 14, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recent Activity',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      Text('Latest actions across the system',
                          style: TextStyle(
                              fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ),
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFFA5D6A7), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                const Text('Live',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFA5D6A7))),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : events.isEmpty
                    ? const Center(
                        child: Text('No recent activity',
                            style: TextStyle(
                                color: AppColors.textTertiary, fontSize: 12)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: events.length > 10 ? 10 : events.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Color(0xFFF0F0F0)),
                        itemBuilder: (_, i) {
                          final e = events[i];
                          final color = _colorForType(e.type);
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Icon(e.icon ?? _iconForType(e.type),
                                  size: 16, color: color),
                            ),
                            title: Text(
                              e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary),
                            ),
                            subtitle: Text(
                              e.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textSecondary),
                            ),
                            trailing: Text(
                              e.timestamp.timeAgo,
                              style: const TextStyle(
                                  fontSize: 10, color: AppColors.textTertiary),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}