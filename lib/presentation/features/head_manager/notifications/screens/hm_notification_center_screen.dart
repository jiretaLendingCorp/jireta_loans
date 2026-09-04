// lib/presentation/features/head_manager/notifications/screens/hm_notification_center_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/models/notification_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../providers/hm_notification_provider.dart';

class HmNotificationCenterScreen extends ConsumerStatefulWidget {
  const HmNotificationCenterScreen({super.key});

  @override
  ConsumerState<HmNotificationCenterScreen> createState() =>
      _HmNotificationCenterScreenState();
}

class _HmNotificationCenterScreenState
    extends ConsumerState<HmNotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmNotificationProvider);
    if (state.unreadCount > 0) {
      Future.microtask(
          () => ref.read(hmNotificationProvider.notifier).markAllRead());
    }

    return WebScaffold(
      title: 'Notification Center',
      actions: [
        if (state.unreadCount > 0)
          TextButton(
            onPressed: () =>
                ref.read(hmNotificationProvider.notifier).markAllRead(),
            child: const Text('Mark All Read',
                style: TextStyle(color: AppColors.deepNavy)),
          ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () =>
              ref.read(hmNotificationProvider.notifier).loadNotifications(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 4),
      ],
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.deepNavy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              tabs: const [
                Tab(text: 'Notifications'),
                Tab(text: 'SMS Logs'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildNotifications(state),
                _buildSmsLogs(state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifications(HmNotificationState state) {
    if (state.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: List.generate(
              5,
              (i) => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: ShimmerLoader(height: 80),
                  )),
        ),
      );
    }
    if (state.notifications.isEmpty) {
      return const EmptyStateWidget(
        title: 'No Notifications',
        message: 'Notifications will appear here',
        icon: Icons.notifications_none,
      );
    }
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(hmNotificationProvider.notifier).loadNotifications(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: state.notifications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _NotifCard(
          key: ValueKey(state.notifications[i].id),
          notif: state.notifications[i],
          onTap: () {
            if (!state.notifications[i].isRead) {
              ref
                  .read(hmNotificationProvider.notifier)
                  .markRead(state.notifications[i].id);
            }
          },
        ),
      ),
    );
  }

  Widget _buildSmsLogs(HmNotificationState state) {
    if (state.smsLogs.isEmpty) {
      return const EmptyStateWidget(
        title: 'No SMS Logs',
        message: 'SMS reminders sent to lenders appear here',
        icon: Icons.sms_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.smsLogs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final log = state.smsLogs[i];
        return ListTile(
          key: ValueKey(log['id']),
          leading: const CircleAvatar(
            backgroundColor: AppColors.infoLight,
            child: Icon(Icons.sms, color: AppColors.info, size: 18),
          ),
          title: Text(log['recipient'] ?? 'Unknown',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(log['message'] ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
          trailing: Text(
            log['sent_at'] != null
                ? DateFormat('MMM d, h:mm a')
                    .format(parseManila(log['sent_at'])!)
                : '',
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        );
      },
    );
  }
}

class _NotifCard extends StatelessWidget {
  final NotificationModel notif;
  final VoidCallback onTap;

  const _NotifCard({super.key, required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notif.isRead ? Colors.white : AppColors.infoLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: notif.isRead
                  ? AppColors.border
                  : AppColors.info.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.deepNavy.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications,
                  size: 18, color: AppColors.deepNavy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(notif.title,
                            style: TextStyle(
                                fontWeight: notif.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w600,
                                fontSize: 13)),
                      ),
                      if (!notif.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.info,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(notif.body,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM d, y h:mm a').format(notif.createdAt),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
