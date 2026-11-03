// lib/presentation/features/head_manager/notifications/screens/hm_notification_center_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/services/fcm_service.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/notification_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../account_deletion/providers/hm_account_deletion_provider.dart';
import '../../account_deletion/screens/hm_account_deletion_screen.dart';
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
  /// Index ng Account Deletion tab. Ang Notifications ang index 0.
  static const int _deletionTab = 1;

  late TabController _tabCtrl;

  /// Ang bawat tab ay may SARILING URI (`/hm/notifications` at
  /// `/hm/account-deletion`), kaya ang URL ang source of truth ng aktibong
  /// tab — tama pa rin ito pagkatapos ng refresh / bookmark / browser back.
  static int _tabIndexFor(String path) =>
      path == RouteConstants.hmAccountDeletion ? _deletionTab : 0;

  int get _activeTab => _tabIndexFor(GoRouterState.of(context).uri.path);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  /// Kapag nagbago ang URL (deep link, back/forward, tab tap) i-sync ang
  /// controller bago mag-build para walang frame na maling tab ang laman.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tab = _tabIndexFor(GoRouterState.of(context).uri.path);
    if (_tabCtrl.index != tab) _tabCtrl.index = tab;
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  /// Header refresh — ang aktibong tab lang ang ni-reload, hindi laging ang
  /// notifications kahit nasa Account Deletion.
  void _refresh() {
    if (_activeTab == _deletionTab) {
      ref.read(hmAccountDeletionProvider.notifier).load(silent: true);
    } else {
      ref.read(hmNotificationProvider.notifier).loadNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _tabIndexFor(GoRouterState.of(context).uri.path);
    final isDeletionTab = activeTab == _deletionTab;
    final state = ref.watch(hmNotificationProvider);
    // Huwag i-mark na read ang notifications kapag nasa Account Deletion tab —
    // hindi pa ito nakikita ng user.
    if (!isDeletionTab && state.unreadCount > 0) {
      Future.microtask(
          () => ref.read(hmNotificationProvider.notifier).markAllRead());
    }

    return WebScaffold(
      // Dati laging "Notification Center" kahit nasa Account Deletion — ngayon
      // sasabay ang header sa aktibong tab.
      title:
          isDeletionTab ? 'Account Deletion Requests' : 'Notification Center',
      actions: [
        if (!isDeletionTab && state.unreadCount > 0)
          TextButton(
            onPressed: () =>
                ref.read(hmNotificationProvider.notifier).markAllRead(),
            child: const Text('Mark All Read',
                style: TextStyle(color: AppColors.deepNavy)),
          ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _refresh,
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
              // Ang URL ang nagpapalit ng tab — kaya naka-go_router ito at
              // hindi lang local controller state.
              onTap: (index) {
                if (index == activeTab) return;
                context.go(index == _deletionTab
                    ? RouteConstants.hmAccountDeletion
                    : RouteConstants.hmNotifications);
              },
              tabs: const [
                Tab(text: 'Notifications'),
                // Dating "SMS Logs" — ang account deletion queue na ngayon ang
                // nasa tab na ito (tinanggal din sa side nav).
                Tab(text: 'Account Deletion'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              // Walang swipe: kung papayagan ito, mababago ang laman pero
              // mananatili ang lumang URI.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildNotifications(state),
                const HmAccountDeletionBody(),
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
            final n = state.notifications[i];
            if (!n.isRead) {
              ref.read(hmNotificationProvider.notifier).markRead(n.id);
            }
            // Open the record this notification is about (same as push taps).
            final path = FcmService.routeFor(
              type: n.type,
              referenceId: n.referenceId ?? '',
              role: AppConstants.roleHeadManager,
            );
            if (path != null && path.isNotEmpty) context.go(path);
          },
        ),
      ),
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
                  // Buong mensahe — dating `maxLines: 2` kaya putol ang
                  // mababasa kapag mahaba ang notification.
                  Text(notif.body,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
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
