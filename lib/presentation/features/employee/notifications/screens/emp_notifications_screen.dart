// lib/presentation/features/employee/notifications/screens/emp_notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../providers/emp_notification_provider.dart';

class EmpNotificationsScreen extends ConsumerWidget {
  const EmpNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(empNotificationProvider);
    if (state.unreadCount > 0) {
      Future.microtask(
          () => ref.read(empNotificationProvider.notifier).markAllRead());
    }

    return WebScaffold(
      title: 'Notifications',
      actions: [
        if (state.unreadCount > 0)
          TextButton.icon(
            onPressed: () =>
                ref.read(empNotificationProvider.notifier).markAllRead(),
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Mark all read'),
          ),
        IconButton(
          onPressed: () =>
              ref.read(empNotificationProvider.notifier).loadNotifications(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
        ),
      ],
      body: state.isLoading
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: ShimmerLoader(height: 80),
            )
          : state.notifications.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.notifications_none_outlined,
                  title: 'No notifications',
                  subtitle: 'You\'re all caught up.',
                )
              : RefreshIndicator(
                  onRefresh: () => ref
                      .read(empNotificationProvider.notifier)
                      .loadNotifications(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.notifications.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final n = state.notifications[i];
                      final isRead = n.isRead;
                      return ListTile(
                        key: ValueKey(n.id),
                        tileColor: isRead
                            ? Colors.transparent
                            : AppColors.deepNavy.withValues(alpha: 0.04),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _typeColor(n.type).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(_typeIcon(n.type),
                              color: _typeColor(n.type), size: 20),
                        ),
                        title: Text(
                          n.title,
                          style: TextStyle(
                            fontWeight:
                                isRead ? FontWeight.w500 : FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.body,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                            Text(
                                DateFormat('MMM d, h:mm a').format(n.createdAt),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary)),
                          ],
                        ),
                        trailing: !isRead
                            ? Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.deepNavy,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                        onTap: () {
                          if (!isRead) {
                            ref
                                .read(empNotificationProvider.notifier)
                                .markRead(id: n.id);
                          }
                        },
                      );
                    },
                  ),
                ),
    );
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'loan':
        return Icons.account_balance_outlined;
      case 'payment':
        return Icons.payment_outlined;
      case 'account_upgrade':
        return Icons.verified_user_outlined;
      case 'collection':
        return Icons.local_shipping_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'loan':
        return AppColors.deepNavy;
      case 'payment':
        return AppColors.riderGreen;
      case 'account_upgrade':
        return AppColors.lenderBlue;
      case 'collection':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }
}
