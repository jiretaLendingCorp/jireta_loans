// lib/presentation/features/rider/notifications/screens/rider_notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/notification_model.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../rider/notifications/providers/rider_notification_provider.dart';
import '../../../../../core/constants/route_constants.dart';

class RiderNotificationsScreen extends ConsumerWidget {
  const RiderNotificationsScreen({super.key});

  static const _navItems = [
    MobileNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: RouteConstants.riderDashboard),
    MobileNavItem(
        icon: Icons.payments_outlined,
        activeIcon: Icons.payments,
        label: 'Collections',
        route: RouteConstants.riderCollections),
    MobileNavItem(
        icon: Icons.search_outlined,
        activeIcon: Icons.search,
        label: 'CI Tasks',
        route: RouteConstants.riderCi),
    MobileNavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.riderProfile),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(riderNotificationProvider);
    // Fallback: if user lands directly on this route (deep-link/refresh),
    // still clear the badge without requiring per-item taps.
    if (state.unreadCount > 0) {
      Future.microtask(
          () => ref.read(riderNotificationProvider.notifier).markAllRead());
    }

    return MobileScaffold(
      title: 'Notifications',
      accentColor: AppColors.riderGreen,
      navItems: _navItems,
      appBarActions: [
        if (state.unreadCount > 0)
          TextButton(
            onPressed: () =>
                ref.read(riderNotificationProvider.notifier).markAllRead(),
            child: const Text('Mark all read',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
      ],
      body: state.isLoading
          ? const ShimmerLoader()
          : RefreshIndicator(
              color: AppColors.riderGreen,
              onRefresh: () =>
                  ref.read(riderNotificationProvider.notifier).refresh(),
              child: state.notifications.isEmpty
                  ? const EmptyStateWidget(message: 'No notifications yet')
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
                      itemCount: state.notifications.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (ctx, i) => _NotificationTile(
                        key: ValueKey(state.notifications[i].id),
                        notification: state.notifications[i],
                        onTap: () {
                          if (!state.notifications[i].isRead) {
                            ref
                                .read(riderNotificationProvider.notifier)
                                .markRead(state.notifications[i].id);
                          }
                        },
                      ),
                    ),
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  const _NotificationTile(
      {super.key, required this.notification, required this.onTap});

  IconData _iconFor(String type) {
    switch (type) {
      case 'ci_assigned':
        return Icons.search;
      case 'collection_assigned':
        return Icons.payments;
      case 'assignment_accepted':
        return Icons.check_circle;
      case 'assignment_declined':
        return Icons.cancel;
      default:
        return Icons.notifications;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'ci_assigned':
        return AppColors.lenderBlue;
      case 'collection_assigned':
        return AppColors.riderGreen;
      case 'assignment_accepted':
        return AppColors.success;
      case 'assignment_declined':
        return AppColors.error;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(notification.type);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: notification.isRead
            ? Colors.transparent
            : AppColors.riderGreen.withValues(alpha: 0.04),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(_iconFor(notification.type), color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                              fontWeight: notification.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: AppColors.riderGreen,
                                shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(notification.body,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(timeago.format(notification.createdAt),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
