// lib/presentation/features/employee/notifications/screens/emp_notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../providers/emp_notification_provider.dart';

class EmpNotificationsScreen extends ConsumerStatefulWidget {
  const EmpNotificationsScreen({super.key});

  @override
  ConsumerState<EmpNotificationsScreen> createState() =>
      _EmpNotificationsScreenState();
}

class _EmpNotificationsScreenState
    extends ConsumerState<EmpNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(empNotificationProvider.notifier).loadList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empNotificationProvider);
    final items = state.valueOrNull?['items'] as List? ?? [];

    return WebScaffold(
      title: 'Notifications',
      actions: [
        TextButton.icon(
          onPressed: () =>
              ref.read(empNotificationProvider.notifier).markRead(),
          icon: const Icon(Icons.done_all, size: 18),
          label: const Text('Mark all read'),
        ),
        IconButton(
          onPressed: () =>
              ref.read(empNotificationProvider.notifier).loadList(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
        ),
      ],
      body: state.isLoading
          ? const ShimmerLoader()
          : items.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.notifications_none_outlined,
                  title: 'No notifications',
                  subtitle: 'You\'re all caught up.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final n = items[i] as Map<String, dynamic>;
                    final isRead = n['is_read'] as bool? ?? false;
                    final title = n['title'] as String? ?? '';
                    final body = n['body'] as String? ?? '';
                    final type = n['type'] as String?;
                    final createdAt = n['created_at'] as String? ?? '';
                    final id = n['id'] as String? ?? '';

                    return ListTile(
                      tileColor: isRead
                          ? Colors.transparent
                          : AppColors.deepNavy.withValues(alpha: 0.04),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _typeColor(type).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_typeIcon(type),
                            color: _typeColor(type), size: 20),
                      ),
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight:
                              isRead ? FontWeight.w500 : FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(body,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                          Text(createdAt,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textTertiary)),
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
                              .markRead(id: id);
                        }
                      },
                    );
                  },
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
