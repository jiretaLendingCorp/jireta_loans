// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
// lib/presentation/features/rider/dashboard/screens/rider_dashboard_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/asset_constants.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_refresh.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart'
    show kDesktopBreakpoint;
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../dashboard/providers/rider_dashboard_provider.dart';
import '../../notifications/providers/rider_notification_provider.dart';
import '../../profile/providers/rider_profile_provider.dart';
import 'widgets/rider_amount_hero.dart';
import 'widgets/rider_live_tracking_card.dart';
import '../../../../../data/models/notification_model.dart';

class RiderDashboardScreen extends ConsumerStatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  ConsumerState<RiderDashboardScreen> createState() =>
      _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends ConsumerState<RiderDashboardScreen> {
  /// `true` habang tumatakbo ang refresh — spinner sa Refresh button ng desktop
  /// top bar at hindi na doble-doble ang pindot.
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderDashboardProvider);
    final profileState = ref.watch(riderProfileProvider);
    final notifState = ref.watch(riderNotificationProvider);
    final riderName = _resolveRiderName(profileState);

    // Sa desktop (≥ [kDesktopBreakpoint]) desktop shell na ang gamit ng rider
    // (sidebar + top bar, tingnan ang `MobileScaffold`) at dalawang-column ang
    // body. Sa mobile, walang binago: isang column pa rin at floating bottom
    // nav.
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    // ── Mga piraso ng dashboard — ISANG pinagmumulan lang ────────────────
    // Pareho ang nilalaman para sa mobile at desktop; ang tanging pinag-iba
    // ay ang PAGKAKA-AYOS (isang column vs. main + rail).
    final sections = _RiderDashboardSections(
      header: _Entrance(
        delay: 0,
        child: _EnterpriseHeader(
          riderName: riderName,
          profilePhotoUrl: profileState.user?.profilePhotoUrl,
          taskCount: state.todayCollections.length +
              state.todayDeliveries.length +
              state.todayCiTasks.length,
        ),
      ),
      filterBar: _Entrance(
        delay: 40,
        child: _CollectionFilterBar(state: state),
      ),
      hero: _Entrance(
        delay: 80,
        child: RiderAmountHero(state: state),
      ),
      tracking: const _Entrance(
        delay: 120,
        child: RiderLiveTrackingCard(),
      ),
      collectionsLabel: _Entrance(
        delay: 180,
        child: _buildSectionLabel(
          context,
          label: 'Collections',
          count: state.todayCollections.length,
          icon: Icons.local_shipping_outlined,
          onMore: () => context.push(RouteConstants.riderCollections),
        ),
      ),
      collections: _Entrance(
        delay: 220,
        child: _buildCollectionTasks(context, state),
      ),
      deliveriesLabel: _Entrance(
        delay: 280,
        child: _buildSectionLabel(
          context,
          label: 'Cash Deliveries',
          count: state.todayDeliveries.length,
          icon: Icons.delivery_dining_outlined,
          onMore: () => context.push(RouteConstants.riderDisbursements),
        ),
      ),
      deliveries: _Entrance(
        delay: 340,
        child: _buildDeliveryTasks(context, state),
      ),
      ciLabel: _Entrance(
        delay: 400,
        child: _buildSectionLabel(
          context,
          label: 'CI Assignments',
          count: state.todayCiTasks.length,
          icon: Icons.search_outlined,
          onMore: () => context.push(RouteConstants.riderCi),
        ),
      ),
      ci: _Entrance(delay: 460, child: _buildCiTasks(context, state)),
      activityLabel: _Entrance(
        delay: 520,
        child: _buildSectionLabel(
          context,
          label: 'Recent Activity',
          count: notifState.notifications.length,
          icon: Icons.notifications_active_outlined,
          onMore: () => context.push(RouteConstants.riderNotifications),
        ),
      ),
      activity: _Entrance(
        delay: 560,
        child: _buildRecentActivity(context, notifState),
      ),
      error: state.error == null ? null : _ErrorBanner(state.error!),
    );

    return MobileScaffold(
      title: 'Rider Home',
      accentColor: AppColors.riderGreen,
      navItems: const [
        MobileNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          label: 'Home',
          route: RouteConstants.riderDashboard,
        ),
        MobileNavItem(
          icon: Icons.delivery_dining_outlined,
          activeIcon: Icons.delivery_dining,
          label: 'Collections',
          route: RouteConstants.riderCollections,
        ),
        MobileNavItem(
          icon: Icons.search_outlined,
          activeIcon: Icons.search,
          label: 'CI Tasks',
          route: RouteConstants.riderCi,
        ),
        MobileNavItem(
          icon: Icons.history_outlined,
          activeIcon: Icons.history_rounded,
          label: 'History',
          route: RouteConstants.riderHistory,
        ),
        MobileNavItem(
          icon: Icons.person_outline,
          activeIcon: Icons.person,
          label: 'Profile',
          route: RouteConstants.riderProfile,
        ),
      ],
      // Sa desktop, nasa top bar ang refresh — hindi kayang i-drag ng mouse ang
      // pull-to-refresh. Sa mobile walang idinadagdag ito (may pull-down doon).
      appBarActions: isDesktop ? [_buildRefreshAction()] : null,
      body: state.isLoading
          ? _buildShimmer(desktop: isDesktop)
          : MobileRefresh(
              color: AppColors.riderGreen,
              // Silent loads: kapag hindi, mag-i-flash ang shimmer sa gitna ng
              // pull-down gesture dahil nagiging `isLoading = true` ang
              // dashboard at napapalitan ang RefreshIndicator mismo.
              onRefresh: _silentRefresh,
              child: isDesktop
                  ? _desktopBody(sections)
                  : _mobileBody(sections),
            ),
    );
  }

  /// Silent refresh para sa pull-down at sa Refresh button ng desktop top bar —
  /// hindi ito nagpapalit ng screen sa shimmer.
  Future<void> _silentRefresh() async {
    await ref.read(riderDashboardProvider.notifier).load(silent: true);
    await ref.read(riderProfileProvider.notifier).loadProfile(silent: true);
  }

  /// Refresh button ng desktop top bar: may nakikitang feedback pagkatapos,
  /// kaya malinaw na gumagana ito.
  Future<void> _onRefreshTap() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await _silentRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Refreshed'),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Widget _buildRefreshAction() {
    return IconButton(
      tooltip: 'Refresh',
      // Habang tumatakbo, spinner ang icon — kitang-kita na may nangyayari.
      onPressed: _refreshing ? null : _onRefreshTap,
      icon: _refreshing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.refresh_rounded, color: Colors.white),
    );
  }

  /// MOBILE na ayos: isang column lang, nakadikit sa floating bottom nav.
  /// Kapareho ito ng dating layout — walang binago sa phone.
  Widget _mobileBody(_RiderDashboardSections s) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          s.header,
          const SizedBox(height: 14),
          s.filterBar,
          const SizedBox(height: 12),
          s.hero,
          const SizedBox(height: 22),
          s.tracking,
          const SizedBox(height: 22),
          s.collectionsLabel,
          const SizedBox(height: 10),
          s.collections,
          const SizedBox(height: 20),
          s.deliveriesLabel,
          const SizedBox(height: 10),
          s.deliveries,
          const SizedBox(height: 20),
          s.ciLabel,
          const SizedBox(height: 10),
          s.ci,
          const SizedBox(height: 20),
          s.activityLabel,
          const SizedBox(height: 10),
          s.activity,
          if (s.error != null) ...[
            const SizedBox(height: 16),
            s.error!,
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// DESKTOP na ayos: pangunahing column (greeting, filter, Total Collected,
  /// live map, Collections) sa kaliwa at makitid na rail (Cash Deliveries, CI
  /// Assignments, Recent Activity) sa kanan. Naka-cap ang lapad (1240) at
  /// naka-center, kaya hindi nakaunat ang mga card sa buong monitor — at wala
  /// nang espasyong nakalaan para sa bottom nav.
  Widget _desktopBody(_RiderDashboardSections s) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    s.header,
                    const SizedBox(height: 16),
                    s.filterBar,
                    const SizedBox(height: 12),
                    s.hero,
                    const SizedBox(height: 22),
                    s.tracking,
                    const SizedBox(height: 24),
                    s.collectionsLabel,
                    const SizedBox(height: 10),
                    s.collections,
                  ],
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    s.deliveriesLabel,
                    const SizedBox(height: 10),
                    s.deliveries,
                    const SizedBox(height: 20),
                    s.ciLabel,
                    const SizedBox(height: 10),
                    s.ci,
                    const SizedBox(height: 20),
                    s.activityLabel,
                    const SizedBox(height: 10),
                    s.activity,
                    if (s.error != null) ...[
                      const SizedBox(height: 20),
                      s.error!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _resolveRiderName(RiderProfileState p) {
    final u = p.user;
    if (u == null) return 'Rider';
    final first = u.firstName.trim();
    final last = u.lastName.trim();
    final full = ('$first $last').trim();
    if (full.isEmpty) return 'Rider';
    return full;
  }

  Widget _buildShimmer({bool desktop = false}) {
    final tiles = List.generate(
      5,
      (_) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: ShimmerLoader(height: 72, borderRadius: 16),
      ),
    );

    if (desktop) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const ShimmerLoader(height: 112, borderRadius: 16),
                      const SizedBox(height: 14),
                      const ShimmerLoader(height: 154, borderRadius: 20),
                      const SizedBox(height: 20),
                      ...tiles,
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 360,
                  child: Column(children: tiles.take(4).toList()),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      child: Column(
        children: [
          const ShimmerLoader(height: 112, borderRadius: 16),
          const SizedBox(height: 14),
          const ShimmerLoader(height: 154, borderRadius: 20),
          const SizedBox(height: 20),
          ...tiles,
        ],
      ),
    );
  }

  Widget _buildSectionLabel(
    BuildContext context, {
    required String label,
    required int count,
    required IconData icon,
    required VoidCallback onMore,
  }) {
    final hasItems = count > 0;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.riderGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: AppColors.riderGreen, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: context.cTextPrimary,
                  ),
                ),
              ),
              if (hasItems) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.riderGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.riderGreen,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (hasItems)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onMore,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'View all',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.riderGreen,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right,
                        size: 16, color: AppColors.riderGreen),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCollectionTasks(
      BuildContext context, RiderDashboardState state) {
    if (state.todayCollections.isEmpty) {
      return _buildEmptyCard(
          'No assigned collection tasks yet', Icons.inbox_outlined);
    }
    return Column(
      children: state.todayCollections.take(5).map<Widget>((c) {
        final lender = c.lenderName;
        final subtitle =
            lender.isNotEmpty ? 'To: $lender' : 'Loan ${c.loanNumber}';
        return _buildTaskCard(
          context,
          title: 'Collection #${c.id.substring(0, 8).toUpperCase()}',
          subtitle: subtitle,
          status: c.statusLabel,
          statusColor: _collStatusColor(context, c.status),
          icon: Icons.two_wheeler,
          iconColor: AppColors.riderGreen,
          onTap: () =>
              context.push('${RouteConstants.riderCollections}/${c.id}'),
        );
      }).toList(),
    );
  }

  Widget _buildDeliveryTasks(BuildContext context, RiderDashboardState state) {
    if (state.todayDeliveries.isEmpty) {
      return _buildEmptyCard(
          'No cash deliveries assigned', Icons.delivery_dining_outlined);
    }
    return Column(
      children: state.todayDeliveries.take(5).map<Widget>((d) {
        final delivery = d.deliveryDate;
        final lender = d.lenderName;
        final subtitle =
            lender.isNotEmpty ? 'To: $lender' : 'Loan ${d.loanNumber}';
        return _buildTaskCard(
          context,
          title: 'Loan ${d.loanNumber}',
          subtitle: delivery != null
              ? '$subtitle · Due ${delivery.toDateString()}'
              : subtitle,
          status: 'Deliver',
          statusColor: AppColors.gold,
          icon: Icons.delivery_dining_outlined,
          iconColor: AppColors.gold,
          onTap: () => context.push(RouteConstants.riderDisbursementUploadProof
              .replaceFirst(':id', d.id)),
        );
      }).toList(),
    );
  }

  Widget _buildCiTasks(BuildContext context, RiderDashboardState state) {
    if (state.todayCiTasks.isEmpty) {
      return _buildEmptyCard('No active CI tasks today', Icons.search_off);
    }
    return Column(
      children: state.todayCiTasks.take(5).map<Widget>((ci) {
        final displayStatus = ci.status == 'accepted' ? 'in_progress' : ci.status;
        return _buildTaskCard(
          context,
          title: 'CI Task #${ci.id.substring(0, 8).toUpperCase()}',
          subtitle: ci.deadline != null
              ? 'Due: ${ci.deadline!.toDateString()}'
              : 'No deadline',
          status: displayStatus,
          statusColor: _ciStatusColor(context, displayStatus),
          icon: Icons.search_outlined,
          iconColor: AppColors.info,
          onTap: () => context.push('${RouteConstants.riderCi}/${ci.id}'),
        );
      }).toList(),
    );
  }

  Widget _buildTaskCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String status,
    required Color statusColor,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: context.cTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 0,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 92),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right,
                    color: context.cTextTertiary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity(
      BuildContext context, RiderNotificationState notifState) {
    final notifications = notifState.notifications;
    if (notifications.isEmpty) {
      return _buildEmptyCard('No recent activity yet', Icons.notifications_none);
    }
    return Column(
      children: notifications.take(5).map<Widget>((n) {
        return _buildActivityTile(context, n);
      }).toList(),
    );
  }

  Widget _buildActivityTile(BuildContext context, NotificationModel n) {
    final (icon, color) = _activityStyle(context, n.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => context.push(RouteConstants.riderNotifications),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 19),
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
                              n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: n.isRead
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                fontSize: 13.5,
                                color: context.cTextPrimary,
                              ),
                            ),
                          ),
                          if (!n.isRead) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.riderGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeAgoManila(n.createdAt),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.cTextTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    color: context.cTextTertiary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (IconData, Color) _activityStyle(BuildContext context, String type) {
    final t = type.toLowerCase();
    if (t.startsWith('ci_') || t == 'ci_required' || t == 'ci_overdue') {
      return (Icons.manage_search_rounded, AppColors.info);
    }
    if (t.startsWith('collection') || t == 'assignment_expired') {
      // Rider icon (motorsiklo), hindi delivery truck — ang rider ang pupunta
      // sa lender, kaya maling simbolo ang truck sa Recent Activity.
      return (Icons.two_wheeler, AppColors.riderGreen);
    }
    if (t.startsWith('disbursement')) {
      return (Icons.delivery_dining_outlined, AppColors.goldDark);
    }
    if (t.startsWith('payment')) {
      return (Icons.payments_outlined, AppColors.success);
    }
    if (t.startsWith('loan')) {
      return (Icons.request_quote_outlined, AppColors.lenderBlue);
    }
    if (t.startsWith('account_upgrade')) {
      return (Icons.verified_user_outlined, AppColors.statusCompleted);
    }
    return (Icons.notifications_outlined, context.cTextSecondary);
  }

  Widget _buildEmptyCard(String message, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.cTextTertiary, size: 36),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Color _collStatusColor(BuildContext context, String s) {
    switch (s) {
      case 'pending':
        return AppColors.statusPending;
      case 'assigned':
        return AppColors.info;
      case 'accepted':
      case 'in_progress':
        return AppColors.riderGreen;
      case 'completed':
        return AppColors.statusCompleted;
      case 'failed':
      case 'declined':
        return AppColors.statusRejected;
      default:
        return context.cTextSecondary;
    }
  }

  Color _ciStatusColor(BuildContext context, String s) {
    switch (s) {
      case 'pending':
        return AppColors.statusPending;
      case 'accepted':
      case 'in_progress':
        return AppColors.info;
      case 'completed':
        return AppColors.statusCompleted;
      case 'declined':
        return AppColors.statusRejected;
      default:
        return context.cTextSecondary;
    }
  }
}

/// Mga piraso ng rider dashboard. Isang beses lang binubuo ang bawat piraso
/// (sa `build`) at ipinapasa sa mobile o desktop na ayos — kaya kapareho ang
/// nilalaman ng dalawa at ang pagkakaayos lang ang nagbabago.
class _RiderDashboardSections {
  final Widget header;
  final Widget filterBar;
  final Widget hero;
  final Widget tracking;
  final Widget collectionsLabel;
  final Widget collections;
  final Widget deliveriesLabel;
  final Widget deliveries;
  final Widget ciLabel;
  final Widget ci;
  final Widget activityLabel;
  final Widget activity;
  final Widget? error;

  const _RiderDashboardSections({
    required this.header,
    required this.filterBar,
    required this.hero,
    required this.tracking,
    required this.collectionsLabel,
    required this.collections,
    required this.deliveriesLabel,
    required this.deliveries,
    required this.ciLabel,
    required this.ci,
    required this.activityLabel,
    required this.activity,
    this.error,
  });
}

// ──────────────────────────────────────────────────────────────
// Enterprise header — time-aware greeting + rider name + jireta logo
// ──────────────────────────────────────────────────────────────
class _EnterpriseHeader extends StatelessWidget {
  final String riderName;
  final String? profilePhotoUrl;
  final int taskCount;
  const _EnterpriseHeader({required this.riderName, this.profilePhotoUrl, required this.taskCount});
  @override
  Widget build(BuildContext context) {
    final now = nowManila();
    final h = now.hour;
    final String greeting;
    final IconData greetingIcon;
    final Color greetingColor;
    if (h >= 5 && h < 12) {
      greeting = 'Good Morning';
      greetingIcon = Icons.wb_sunny_rounded;
      greetingColor = const Color(0xFFE9A23B);
    } else if (h >= 12 && h < 18) {
      greeting = 'Good Afternoon';
      greetingIcon = Icons.light_mode_rounded;
      greetingColor = AppColors.goldDark;
    } else {
      greeting = 'Good Evening';
      greetingIcon = Icons.nights_stay_rounded;
      greetingColor = const Color(0xFF4A5A78);
    }
    const subText = '';
    final initials = riderName.trim().isEmpty ? 'R' : riderName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    // NO CARD ΓÇö text only, profile left, hi right, logo left upper, visible borders
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Jireta logo ΓÇö RIGHT side, black visible border, BILOG fit
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1.6),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 7, offset: const Offset(0, 2))],
              ),
              child: ClipOval(
                child: Image.asset(AssetConstants.logoJpg, fit: BoxFit.cover, width: 30, height: 30, errorBuilder: (_, __, ___) => Icon(Icons.shield_rounded, size: 15, color: Colors.black)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 38, top: 0, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile picture ΓÇö LEFT side, visible black edge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2.2),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 10, offset: const Offset(0, 3)), BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      alignment: Alignment.center,
                      child: ClipOval(
                        child: profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty
                            ? Image.network(profilePhotoUrl!, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initialsText(initials))
                            : _initialsText(initials),
                      ),
                    ),
                    Positioned(right: -1, bottom: -1, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: AppColors.riderGreen, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
                  ],
                ),
                const SizedBox(width: 12),
                // Hi + name ΓÇö RIGHT side of profile picture, text only
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Builder(builder: (_) {
                            // Dark mode: mas maliwanag na greeting color + mas
                            // matapang na pill para visible (dati lubog ang
                            // orange sa dark background).
                            final isDark = context.isDarkMode;
                            final pillFg = isDark
                                ? const Color(0xFFFFC766)
                                : greetingColor;
                            return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                    color: pillFg.withValues(
                                        alpha: isDark ? 0.22 : 0.11),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: pillFg.withValues(
                                            alpha: isDark ? 0.45 : 0.16))),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(greetingIcon, size: 11, color: pillFg),
                                  const SizedBox(width: 3),
                                  Text(greeting.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.7,
                                          color: pillFg))
                                ]));
                          }),
                          // Plain text lang ang date — hindi na mukhang button.
                          Text(now.formatted,
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: context.cTextSecondary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Hi, $riderName!', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.cTextPrimary, letterSpacing: -0.3, height: 1.1)),
                      const SizedBox(height: 2),
                      Text(subText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: context.cTextSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _initialsText(String initials) => Text(initials, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.riderGreen, letterSpacing: 0.5));
}

// ──────────────────────────────────────────────────────────────
// Monthly + exact-date filter for Total Collected
// ──────────────────────────────────────────────────────────────
class _CollectionFilterBar extends ConsumerWidget {
  final RiderDashboardState state;
  const _CollectionFilterBar({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(riderDashboardProvider.notifier);
    // Default na ang kasalukuyang buwan, kaya hindi na kailangan ng "clear"
    // button hangga't wala pang ibang period/date na pinili.
    final hasFilter = state.selectedDate != null ||
        (state.selectedMonth != null &&
            state.selectedMonth != RiderDashboardNotifier.currentMonthKey());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined, size: 18, color: AppColors.riderGreen),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: state.selectedMonth,
                hint: Text('Monthly — All time',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.cTextSecondary)),
                isDense: true,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.cTextPrimary),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All time')),
                  ...RiderDashboardNotifier.availableMonths().map((m) =>
                      DropdownMenuItem<String?>(
                          value: m,
                          child: Text(RiderDashboardNotifier.monthLabel(m)))),
                ],
                onChanged: (v) => notifier.setMonth(v),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () async {
              final initial = state.selectedDate != null
                  ? DateTime.tryParse(state.selectedDate!) ?? DateTime.now()
                  : DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) await notifier.setDate(picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: state.selectedDate != null
                    ? AppColors.riderGreen
                    : AppColors.riderGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_rounded,
                      size: 15,
                      color: state.selectedDate != null
                          ? Colors.white
                          : AppColors.riderGreen),
                  const SizedBox(width: 5),
                  Text(
                    state.selectedDate ?? 'Exact date',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: state.selectedDate != null
                            ? Colors.white
                            : AppColors.riderGreen),
                  ),
                ],
              ),
            ),
          ),
          if (hasFilter) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () => notifier.clearFilters(),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded,
                    size: 16, color: context.cTextSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Enterprise: primary amount hero (full-width, distinct from metrics)
// ──────────────────────────────────────────────────────────────
// Vibrant primary — Total Collected (enterprise + vibrant)
// ──────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String error;
  const _ErrorBanner(this.error);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fade + slide + scale entrance — matches HM/Employee dashboards.
class _Entrance extends StatefulWidget {
  final Widget child;
  final int delay;
  const _Entrance({required this.child, this.delay = 0});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  late final Animation<double> _scale;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curved);
    _scale = Tween<double>(begin: 0.97, end: 1).animate(curved);
    _timer = Timer(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}
