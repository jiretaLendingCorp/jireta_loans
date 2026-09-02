// lib/presentation/shared/widgets/layout/mobile_scaffold.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final bool centerTitle;

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
    this.centerTitle = false,
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
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        extendBody: true,
        extendBodyBehindAppBar: false,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        appBar: AppBar(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: centerTitle,
          title: title.isEmpty
              ? null
              : Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
          automaticallyImplyLeading: showBackButton && appBarLeading == null,
          leading: appBarLeading ??
              (showBackButton
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          context.go(RouteConstants.lenderDashboard);
                        }
                      },
                    )
                  : null),
          actions: [
            if (isLender)
              IconButton(
                tooltip: 'Contact',
                onPressed: () => _showLenderContactSheet(context),
                icon: const Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                ),
              ),
            if (showNotificationsBell) ...[
              IconButton(
                onPressed: () {
                  // Clear badge instantly when bell is tapped — no need to tap each item.
                  if (unreadCount > 0) {
                    if (isLender) {
                      ref.read(lenderNotificationProvider.notifier).markAllRead();
                    } else {
                      ref.read(riderNotificationProvider.notifier).markAllRead();
                    }
                  }
                  context.go(notificationsRoute);
                },
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
    return SafeArea(
      top: false,
      bottom: true,
      minimum: const EdgeInsets.only(bottom: 0),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          // Raised a bit more + vibrant per request — 36px above SafeArea
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 36),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 336),
            child: Container(
              // PREMIUM — compressed, vibrant, floated
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.white, Color(0xFFFCFCFA)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.44),
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.14),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.14),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: _buildModernItems(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildModernItems(BuildContext context) {
    return items.asMap().entries.map((e) {
      final i = e.key;
      final item = e.value;
      final isSelected = currentIndex == i;
      // Negative if no match (e.g., deep route) -> none selected, treat as 0? keep none
      final effectiveSelected = currentIndex >= 0 && isSelected;

      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap(i);
              },
              borderRadius: BorderRadius.circular(22),
              splashColor: accentColor.withValues(alpha: 0.10),
              highlightColor: accentColor.withValues(alpha: 0.06),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: effectiveSelected
                      ? LinearGradient(
                          colors: [
                            accentColor,
                            accentColor.withValues(alpha: 0.88),
                            AppColors.gold.withValues(alpha: 0.92),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: effectiveSelected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: effectiveSelected
                        ? Colors.white.withValues(alpha: 0.65)
                        : Colors.transparent,
                    width: effectiveSelected ? 1 : 1,
                  ),
                  boxShadow: effectiveSelected
                      ? [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: effectiveSelected ? 26 : 24,
                          height: effectiveSelected ? 26 : 24,
                          decoration: BoxDecoration(
                            color: effectiveSelected
                                ? Colors.white.withValues(alpha: 0.20)
                                : accentColor.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Icon(
                          effectiveSelected ? item.activeIcon : item.icon,
                          size: effectiveSelected ? 20 : 19,
                          weight: 700,
                          color: effectiveSelected
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                        if ((item.badgeCount ?? 0) > 0)
                          Positioned(
                            top: -6,
                            right: -8,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 16),
                              height: 16,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.white, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.error
                                        .withValues(alpha: 0.35),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                (item.badgeCount! > 99)
                                    ? '99+'
                                    : '${item.badgeCount}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  height: 1,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.15,
                        height: 1.1,
                        color: effectiveSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
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
        icon: Icons.delivery_dining_outlined,
        activeIcon: Icons.delivery_dining,
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
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long,
        label: 'History',
        route: RouteConstants.lenderPaymentHistory,
      ),
      const MobileNavItem(
        icon: Icons.person_outlined,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.lenderProfile,
      ),
    ];

void _showLenderContactSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.deepNavy,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Contact Us', style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deepNavy)),
                      Text('We\'re here to help', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 16),
            _ContactSheetRow(
              icon: Icons.mail_outline_rounded,
              title: 'Email',
              subtitle: 'jireyalendingcorp@gmail.com',
              onTap: () async {
                final uri = Uri.parse('mailto:jireyalendingcorp@gmail.com');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
            const SizedBox(height: 12),
            _ContactSheetRow(
              icon: Icons.phone_outlined,
              title: 'Phone',
              subtitle: '09755849954',
              onTap: () async {
                final uri = Uri.parse('tel:09755849954');
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
            const SizedBox(height: 12),
            _ContactSheetRow(
              icon: Icons.access_time_rounded,
              title: 'Office Hours',
              subtitle: 'Mon - Fri, 8:00 AM - 5:00 PM',
              onTap: null,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ContactSheetRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _ContactSheetRow({required this.icon, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 18, color: AppColors.deepNavy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 0.3)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.deepNavy)),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
