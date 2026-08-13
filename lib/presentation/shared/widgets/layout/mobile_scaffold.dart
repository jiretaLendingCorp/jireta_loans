// lib/presentation/shared/widgets/layout/mobile_scaffold.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../features/lender/notifications/providers/lender_notification_provider.dart';
import '../../../features/rider/notifications/providers/rider_notification_provider.dart';
import '../notification_badge.dart';

class MobileScaffold extends ConsumerWidget {
  final String title;
  final Widget body;
  final List<MobileNavItem> navItems;
  final Color accentColor;
  final Widget? floatingActionButton;
  final List<Widget>? appBarActions;
  final Widget? appBarLeading;
  final bool showBackButton;
  final bool resizeToAvoidBottomInset;
  final bool showBottomNav;
  final bool showNotificationsBell;

  const MobileScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.navItems,
    this.accentColor = AppColors.deepNavy,
    this.floatingActionButton,
    this.appBarActions,
    this.appBarLeading,
    this.showBackButton = false,
    this.resizeToAvoidBottomInset = true,
    this.showBottomNav = true,
    this.showNotificationsBell = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final currentIndex = navItems.indexWhere(
      (item) => path == item.route || path.startsWith('${item.route}/'),
    );

    final isLender = path.startsWith('/lender');
    final notificationsRoute = isLender
        ? RouteConstants.lenderNotifications
        : RouteConstants.riderNotifications;
    final unreadCount = isLender
        ? ref.watch(lenderNotificationProvider).unreadCount
        : ref.watch(riderNotificationProvider).unreadCount;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        appBar: AppBar(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: title.isEmpty ? null : Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          automaticallyImplyLeading: showBackButton && appBarLeading == null,
          leading: appBarLeading,
          actions: [
            if (showNotificationsBell) ...[
              IconButton(
                onPressed: () => context.go(notificationsRoute),
                icon: NotificationBadge(
                  count: unreadCount,
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            ...?appBarActions,
          ],
        ),
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: !showBottomNav || navItems.isEmpty
            ? null
            : RepaintBoundary(
                child: _FloatingBottomNav(
                  items: navItems,
                  currentIndex: currentIndex,
                  accentColor: accentColor,
                  onTap: (i) => context.go(navItems[i].route),
                ),
              ),
      ),
    );
  }
}

class MobileNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  final int? badgeCount;

  const MobileNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
    this.badgeCount,
  });
}

class _FloatingBottomNav extends StatelessWidget {
  final List<MobileNavItem> items;
  final int currentIndex;
  final Color accentColor;
  final void Function(int) onTap;

  const _FloatingBottomNav({
    required this.items,
    required this.currentIndex,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: _buildItems(context),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildItems(BuildContext context) {
    return items.asMap().entries.map((e) {
      final i = e.key;
      final item = e.value;
      final isSelected = currentIndex == i;

      return Expanded(
        child: KeyedSubtree(
          key: ValueKey(item.route),
          child: GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accentColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: Icon(
                            isSelected ? item.activeIcon : item.icon,
                            key: ValueKey(isSelected),
                            size: 21,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                      if ((item.badgeCount ?? 0) > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${item.badgeCount}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color:
                          isSelected ? accentColor : AppColors.textTertiary,
                      fontFamily: 'Inter',
                    ),
                    child: Text(item.label),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

// Rider nav builder
List<MobileNavItem> riderNavItems() => [
      const MobileNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: RouteConstants.riderDashboard,
      ),
      const MobileNavItem(
        icon: Icons.local_shipping_outlined,
        activeIcon: Icons.local_shipping,
        label: 'Collections',
        route: RouteConstants.riderCollections,
      ),
      const MobileNavItem(
        icon: Icons.search_outlined,
        activeIcon: Icons.search,
        label: 'CI Tasks',
        route: RouteConstants.riderCi,
      ),
      const MobileNavItem(
        icon: Icons.person_outlined,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.riderProfile,
      ),
    ];

// Lender nav builder
List<MobileNavItem> lenderNavItems() => [
      const MobileNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: RouteConstants.lenderDashboard,
      ),
      const MobileNavItem(
        icon: Icons.payments_outlined,
        activeIcon: Icons.payments,
        label: 'Payments',
        route: RouteConstants.lenderPayments,
      ),
      const MobileNavItem(
        icon: Icons.person_outlined,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.lenderProfile,
      ),
    ];
