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

/// Maps a raw audit log entry into a feed event.
ActivityEvent _mapAuditLog(Map<String, dynamic> log) {
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
    timestamp: DateTime.tryParse(log['created_at']?.toString() ?? '') ??
        DateTime.now(),
    type: action,
  );
}

/// Latest audit entries mapped into feed events for the dashboard.
final hmRecentActivityProvider =
    FutureProvider<List<ActivityEvent>>((ref) async {
  final res = await sl<AuditRemoteDataSource>().getLogs(limit: 10);
  final items = (res['data'] as List?) ?? [];
  return items.map((raw) => _mapAuditLog(raw as Map<String, dynamic>)).toList();
});

/// All audit entries (paginated through) for the "View All" modal.
final hmAllActivityProvider =
    FutureProvider<List<ActivityEvent>>((ref) async {
  final ds = sl<AuditRemoteDataSource>();
  final List<ActivityEvent> all = [];
  final first = await ds.getLogs(page: 1, limit: 100);
  final meta = (first['meta'] as Map<String, dynamic>?) ?? {};
  final totalPages = (meta['total_pages'] as num?)?.toInt() ?? 1;
  all.addAll((first['data'] as List? ?? [])
      .map((raw) => _mapAuditLog(raw as Map<String, dynamic>)));
  for (var page = 2; page <= totalPages; page++) {
    final res = await ds.getLogs(page: page, limit: 100);
    all.addAll((res['data'] as List? ?? [])
        .map((raw) => _mapAuditLog(raw as Map<String, dynamic>)));
  }
  return all;
});

class HmActivityFeed extends ConsumerWidget {
  final List<ActivityEvent> events;
  final bool isLoading;

  const HmActivityFeed(
      {super.key, required this.events, this.isLoading = false});

  void _openViewAll(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final allAsync = ref.watch(hmAllActivityProvider);
        return Dialog(
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            Text('All Activity',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                            Text('Complete audit trail across the system',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white70)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded,
                            size: 18, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: allAsync.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (e, _) => Center(
                        child: Text('Failed to load activity: $e',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.error))),
                    data: (all) => all.isEmpty
                        ? const Center(
                            child: Text('No activity recorded',
                                style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12)),
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
                            itemCount: all.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: Color(0xFFF0F0F0)),
                            itemBuilder: (_, i) {
                              final e = all[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            e.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            e.subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      e.timestamp.timeAgo,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textTertiary),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                TextButton.icon(
                  onPressed: () => _openViewAll(context, ref),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded,
                      size: 13, color: Colors.white),
                  label: const Text('View All',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
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
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        e.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        e.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  e.timestamp.timeAgo,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textTertiary),
                                ),
                              ],
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