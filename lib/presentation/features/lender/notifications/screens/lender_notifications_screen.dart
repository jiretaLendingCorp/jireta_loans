// lib/presentation/features/lender/notifications/screens/lender_notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/lender_notification_provider.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
  MobileNavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'History',
      route: RouteConstants.lenderPaymentHistory),

  MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile),
];

class LenderNotificationsScreen extends ConsumerStatefulWidget {
  const LenderNotificationsScreen({super.key});

  @override
  ConsumerState<LenderNotificationsScreen> createState() => _State();
}

class _State extends ConsumerState<LenderNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(lenderNotificationProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderNotificationProvider);
    if (state.unreadCount > 0) {
      Future.microtask(
          () => ref.read(lenderNotificationProvider.notifier).markAllRead());
    }

    return MobileScaffold(
      title: 'Notifications',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      appBarActions: [
        if (state.notifications.any((n) => !n.isRead))
          TextButton(
            onPressed: () =>
                ref.read(lenderNotificationProvider.notifier).markAllRead(),
            child: const Text('Mark all read',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
      ],
      body: state.isLoading
          ? const ShimmerLoader()
          : state.notifications.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.notifications_none,
                  title: 'No Notifications',
                  subtitle:
                      'Loan updates, payment reminders, and alerts will appear here.',
                )
              : RefreshIndicator(
                  color: AppColors.lenderBlue,
                  onRefresh: () =>
                      ref.read(lenderNotificationProvider.notifier).load(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 108),
                    itemCount: state.notifications.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (ctx, i) => _NotifTile(
                        key: ValueKey(state.notifications[i].id),
                        item: state.notifications[i],
                        onTap: () {
                          if (!state.notifications[i].isRead) {
                            ref
                                .read(lenderNotificationProvider.notifier)
                                .markRead(state.notifications[i].id);
                          }
                        }),
                  ),
                ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final dynamic item;
  final VoidCallback onTap;
  const _NotifTile({super.key, required this.item, required this.onTap});

  IconData _icon(String type) {
    switch (type) {
      case 'loan_approved':
        return Icons.check_circle_outline;
      case 'loan_rejected':
        return Icons.cancel_outlined;
      case 'payment_due':
        return Icons.payments_outlined;
      case 'payment_confirmed':
        return Icons.done_all_outlined;
      case 'disbursement':
        return Icons.account_balance_wallet_outlined;
      case 'collection':
        return Icons.delivery_dining_outlined;
      case 'account_upgrade':
        return Icons.verified_user_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'loan_approved':
        return AppColors.success;
      case 'loan_rejected':
        return AppColors.error;
      case 'payment_due':
        return AppColors.warning;
      case 'payment_confirmed':
        return AppColors.info;
      case 'disbursement':
        return AppColors.riderGreen;
      default:
        return AppColors.lenderBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = item.isRead;
    final isRead = raw is bool ? raw : (raw?.toString().toLowerCase() == 'true' || raw?.toString() == '1');
    final type = item.type as String? ?? '';
    final title = item.title as String? ?? '';
    final body = item.body as String? ?? '';
    final createdAt = item.createdAt;
    final color = _color(type);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isRead
            ? Colors.transparent
            : AppColors.lenderBlue.withValues(alpha: 0.04),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: Icon(_icon(type), color: color, size: 22),
                ),
                if (!isRead)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.lenderBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      timeago.format(createdAt is DateTime
                          ? ensureManila(createdAt)
                          : ensureManila(DateTime.tryParse(createdAt.toString()) ??
                              nowManila())),
                      style: TextStyle(
                          fontSize: 11,
                          color: isRead
                              ? AppColors.textTertiary
                              : AppColors.lenderBlue),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
