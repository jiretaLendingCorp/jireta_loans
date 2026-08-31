// lib/presentation/shared/widgets/layout/web_scaffold.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/user_model.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/employee/profile/providers/emp_profile_provider.dart';
import '../../../features/head_manager/profile/providers/hm_profile_provider.dart';
import '../../../features/head_manager/notifications/providers/hm_notification_provider.dart';
import '../../../features/employee/notifications/providers/emp_notification_provider.dart';
import '../../providers/auth_state_provider.dart';
import '../notification_badge.dart';
import '../profile_avatar.dart';

final _sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// Remembers the sidebar's scroll offset across route changes. Every page
/// builds its own sidebar (flat routes), so without this the list snaps back
/// to the top whenever you navigate — making it look like the nav "resets"
/// after tapping an item near the bottom.
final _sidebarScrollOffsetProvider = StateProvider<double>((ref) => 0);

/// Tracks which expandable sidebar groups are currently expanded (by label).
/// Persisted across route changes so manual toggle doesn't reset on navigation.
final _sidebarExpandedGroupsProvider =
    StateProvider<Set<String>>((ref) => <String>{});

/// Flyout open state for People - persists across navigation so the 5 items
/// stay visible when People is selected (click People -> show All Users etc.).
final _peopleFlyoutOpenProvider = StateProvider<bool>((ref) => false);

const double _desktopBreakpoint = 900;

class WebScaffold extends ConsumerWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const WebScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(_sidebarCollapsedProvider);
    final authState = ref.watch(authStateProvider);
    final role = authState.role ?? '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;

        if (isDesktop) {
          return Scaffold(
            backgroundColor: const Color(0xFFF0F2F5),
            body: Row(
              children: [
                RepaintBoundary(
                  child: _Sidebar(collapsed: collapsed, role: role),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(
                        title: title,
                        actions: actions,
                        onMenuTap: () => ref
                            .read(_sidebarCollapsedProvider.notifier)
                            .state = !collapsed,
                        authState: authState,
                      ),
                      Expanded(
                        child: _buildBody(floatingActionButton),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF0F2F5),
          appBar: AppBar(
            backgroundColor: const Color(0xFFF0F2F5),
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            automaticallyImplyLeading: false,
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, color: AppColors.textSecondary),
                tooltip: 'Open Menu',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...?actions,
                      _MobileActions(authState: authState),
                    ],
                  ),
                ),
              ),
            ],
          ),
          drawer: Drawer(
            width: 280,
            child: SafeArea(
              child: _Sidebar(collapsed: false, role: role, inDrawer: true),
            ),
          ),
          body: _buildBody(floatingActionButton),
        );
      },
    );
  }

  Widget _buildBody(Widget? floatingActionButton) {
    return Stack(
      children: [
        body,
        if (floatingActionButton != null)
          Positioned(
            bottom: 24,
            right: 24,
            child: floatingActionButton,
          ),
      ],
    );
  }
}

class _MobileActions extends ConsumerWidget {
  final AuthState authState;
  const _MobileActions({required this.authState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = authState.role ?? '';
    void onNotificationTap() {
      if (role == AppConstants.roleHeadManager) {
        if (ref.read(hmNotificationProvider).unreadCount > 0) {
          ref.read(hmNotificationProvider.notifier).markAllRead();
        }
        context.go(RouteConstants.hmNotifications);
      } else if (role == AppConstants.roleEmployee) {
        if (ref.read(empNotificationProvider).unreadCount > 0) {
          ref.read(empNotificationProvider.notifier).markAllRead();
        }
        context.go(RouteConstants.empNotifications);
      }
    }

    final unread = role == AppConstants.roleHeadManager
        ? ref.watch(hmNotificationProvider).unreadCount
        : role == AppConstants.roleEmployee
            ? ref.watch(empNotificationProvider).unreadCount
            : 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onNotificationTap,
          icon: NotificationBadge(
            count: unread,
            child: const Icon(
              Icons.notifications_outlined,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        _UserAvatar(authState: authState, showName: false),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final VoidCallback onMenuTap;
  final AuthState authState;

  const _TopBar({
    required this.title,
    this.actions,
    required this.onMenuTap,
    required this.authState,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenuTap,
            icon: const Icon(Icons.menu, color: AppColors.textSecondary),
            tooltip: 'Toggle Sidebar',
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (actions != null) ...actions!,
          const SizedBox(width: 8),
          Consumer(
            builder: (context, ref, _) {
              final role = authState.role ?? '';
              final unread = role == AppConstants.roleHeadManager
                  ? ref.watch(hmNotificationProvider).unreadCount
                  : role == AppConstants.roleEmployee
                      ? ref.watch(empNotificationProvider).unreadCount
                      : 0;
              void onNotificationTap() {
                if (role == AppConstants.roleHeadManager) {
                  if (ref.read(hmNotificationProvider).unreadCount > 0) {
                    ref.read(hmNotificationProvider.notifier).markAllRead();
                  }
                  context.go(RouteConstants.hmNotifications);
                } else if (role == AppConstants.roleEmployee) {
                  if (ref.read(empNotificationProvider).unreadCount > 0) {
                    ref.read(empNotificationProvider.notifier).markAllRead();
                  }
                  context.go(RouteConstants.empNotifications);
                }
              }

              return IconButton(
                onPressed: onNotificationTap,
                icon: NotificationBadge(
                  count: unread,
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          _UserAvatar(authState: authState),
        ],
      ),
    );
  }
}

class _UserAvatar extends ConsumerWidget {
  final AuthState authState;
  /// When true, shows the user's full name beside the avatar (desktop header).
  /// When false, shows only the circular avatar (mobile compact header).
  final bool showName;
  const _UserAvatar({required this.authState, this.showName = true});

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'U';
    final parts =
        trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      final w = parts[0];
      if (w.length >= 2) return (w[0] + w[1]).toUpperCase();
      return w[0].toUpperCase();
    }
    // first + last -> "Juan Dela Cruz" => JC, "Juan Cruz" => JC
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = authState.role;
    UserModel? profileUser;
    if (role == AppConstants.roleHeadManager) {
      profileUser = ref.watch(hmProfileProvider).user;
    } else if (role == AppConstants.roleEmployee) {
      profileUser = ref.watch(empProfileProvider).valueOrNull;
    }

    final user = profileUser ?? authState.user;
    final name = user?.fullName ?? '';
    final displayName = name.trim().isNotEmpty
        ? name.trim()
        : (user?.email ?? 'User');
    final initials = _getInitials(name);
    final photoUrl =
        profileUser?.profilePhotoUrl ?? authState.user?.profilePhotoUrl;
    final roleLabel = (authState.role ?? '').replaceAll('_', ' ');

    final avatar = ProfileAvatar(
      photoUrl: photoUrl,
      name: name,
      color: AppColors.deepNavy,
      radius: 18,
      borderColor: Colors.black,
      fallback: Text(
        initials,
        style: TextStyle(
          fontSize: initials.length == 1 ? 14 : 12,
          fontWeight: FontWeight.w700,
          color: AppColors.gold,
          letterSpacing: initials.length == 1 ? 0 : 0.5,
        ),
      ),
    );

    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          if (showName) ...[
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (roleLabel.isNotEmpty)
                    Text(
                      roleLabel.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                        letterSpacing: 0.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ],
      ),
      onSelected: (val) async {
        if (val == 'profile') {
          final role = authState.role;
          if (role == AppConstants.roleHeadManager) {
            context.go(RouteConstants.hmProfile);
          } else if (role == AppConstants.roleEmployee) {
            context.go(RouteConstants.empProfile);
          }
        } else if (val == 'logout') {
          // Prevent double-tap while logout overlay is visible.
          if (ref.read(authStateProvider).isLoggingOut) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Log Out'),
              content: const Text('Do you want to logout?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('No')),
                ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Yes'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          // Global [LogoutOverlay] appears automatically via
          // authStateProvider.isLoggingOut — no manual dialog needed.
          await ref.read(authProvider.notifier).logout();
          if (context.mounted) context.go(RouteConstants.webLogin);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                authState.role?.replaceAll('_', ' ').toUpperCase() ?? '',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              Icon(Icons.person_outlined, size: 18),
              SizedBox(width: 10),
              Text('My Profile'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: AppColors.error),
              SizedBox(width: 10),
              Text('Log Out', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends ConsumerStatefulWidget {
  final bool collapsed;
  final String role;
  final bool inDrawer;

  const _Sidebar({
    required this.collapsed,
    required this.role,
    this.inDrawer = false,
  });

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    // Start where the user left off on the previous page's sidebar.
    _scrollCtrl = ScrollController(
      initialScrollOffset: ref.read(_sidebarScrollOffsetProvider),
    );
    _scrollCtrl.addListener(_saveOffset);
  }

  void _saveOffset() {
    if (_scrollCtrl.hasClients) {
      ref.read(_sidebarScrollOffsetProvider.notifier).state =
          _scrollCtrl.offset;
    }
  }

  @override
  void dispose() {
    _saveOffset();
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool _isActivePath(String path, String route) =>
      route.isNotEmpty && (path == route || path.startsWith('$route/'));

  bool _isGroupChildActive(String path, _NavItem group) =>
      group.children.any((c) => _isActivePath(path, c.route));

  void _toggleGroup(String label) {
    final current = ref.read(_sidebarExpandedGroupsProvider);
    final next = Set<String>.from(current);
    if (next.contains(label)) {
      next.remove(label);
    } else {
      next.add(label);
    }
    ref.read(_sidebarExpandedGroupsProvider.notifier).state = next;
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.collapsed;
    final role = widget.role;
    final inDrawer = widget.inDrawer;
    final effectiveCollapsed = inDrawer ? false : collapsed;
    final items = role == AppConstants.roleHeadManager
        ? _hmItems(context)
        : _empItems(context);
    final w = inDrawer ? double.infinity : (collapsed ? 68.0 : 240.0);
    final path = GoRouterState.of(context).uri.path;
    final expandedGroups = ref.watch(_sidebarExpandedGroupsProvider);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: w,
      decoration: const BoxDecoration(
        color: AppColors.deepNavy,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(2, 0)),
        ],
      ),
      child: Column(
        children: [
          _SidebarHeader(collapsed: effectiveCollapsed),
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: items.map((item) {
                if (item.isGroup) {
                  if (inDrawer) {
                    // Drawer (mobile): use inline accordion expandable.
                    final childActive = _isGroupChildActive(path, item);
                    final isExpanded =
                        expandedGroups.contains(item.label) || childActive;
                    return _SidebarGroup(
                      item: item,
                      collapsed: effectiveCollapsed,
                      isExpanded: isExpanded,
                      onToggle: () => _toggleGroup(item.label),
                      onExpandSidebar: () {
                        if (collapsed) {
                          ref.read(_sidebarCollapsedProvider.notifier).state =
                              false;
                          if (!expandedGroups.contains(item.label)) {
                            _toggleGroup(item.label);
                          }
                        }
                      },
                    );
                  }
                  // Desktop (both collapsed & expanded): Flyout menu.
                  return _FlyoutNavGroup(
                    item: item,
                    collapsed: effectiveCollapsed,
                    sidebarWidth: collapsed ? 68.0 : 240.0,
                  );
                }
                return _SidebarItem(
                  item: item,
                  collapsed: effectiveCollapsed,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<_NavItem> _hmItems(BuildContext ctx) => [
        const _NavItem(
            Icons.dashboard_outlined, 'Dashboard', RouteConstants.hmDashboard),
        // Flyout: "People" is grouping only (no route) - clicking shows box with 5,
        // no child pre-selected. Must pick one, then box disappears.
        const _NavItem(
          Icons.groups_outlined,
          'People',
          '',
          [
            _NavItem(
                Icons.group_outlined, 'All People', RouteConstants.hmAllUsers),
            _NavItem(
                Icons.badge_outlined, 'Employees', RouteConstants.hmEmployees),
            _NavItem(Icons.delivery_dining_outlined, 'Riders',
                RouteConstants.hmRiders),
            _NavItem(
                Icons.person_outline, 'Lenders', RouteConstants.hmLenders),
            _NavItem(
                Icons.archive_outlined, 'Archived', RouteConstants.hmArchived),
          ],
        ),
        const _NavItem(
          Icons.description_outlined,
          'Loan Records',
          RouteConstants.hmLoanApplications,
        ),
        const _NavItem(Icons.verified_user_outlined, 'Lender Account Upgrade',
            RouteConstants.hmAccountUpgrade),
        const _NavItem(
          Icons.search_outlined,
          'Credit Investigation',
          RouteConstants.hmCi,
        ),
        const _NavItem(
          Icons.delivery_dining_outlined,
          'Collections',
          RouteConstants.hmCollections,
        ),
        const _NavItem(
            Icons.assessment_outlined, 'Reports', RouteConstants.hmReports),
        const _NavItem(
            Icons.history_outlined, 'Audit Logs', RouteConstants.hmAudit),
      ];

  List<_NavItem> _empItems(BuildContext ctx) => [
        const _NavItem(
          Icons.dashboard_outlined,
          'Dashboard',
          RouteConstants.empDashboard,
        ),
        // Employee also gets the same nested People grouping for consistency
        // (Lenders + Riders under People). Archived is Head Manager only.
        const _NavItem(
          Icons.groups_outlined,
          'People',
          '',
          [
            _NavItem(
                Icons.person_outline, 'Lenders', RouteConstants.empLenders),
            _NavItem(Icons.delivery_dining_outlined, 'Riders',
                RouteConstants.empRiders),
          ],
        ),
        const _NavItem(
          Icons.description_outlined,
          'Loan Records',
          RouteConstants.empLoans,
        ),
        const _NavItem(Icons.verified_user_outlined, 'Lender Account Upgrade',
            RouteConstants.empAccountUpgrade),
        const _NavItem(
          Icons.search_outlined,
          'Credit Investigation',
          RouteConstants.empCi,
        ),
        const _NavItem(
          Icons.delivery_dining_outlined,
          'Collections',
          RouteConstants.empCollections,
        ),
      ];
}

class _SidebarHeader extends StatelessWidget {
  final bool collapsed;
  const _SidebarHeader({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.7)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(AssetConstants.logoJpg, fit: BoxFit.cover),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'JIRETA',
                    style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.gold,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    'LOANS & CREDIT',
                    style: TextStyle(
                      fontSize: 8,
                      color: Colors.white38,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String route;
  final List<_NavItem> children;
  const _NavItem(this.icon, this.label, this.route,
      [this.children = const []]);

  bool get isGroup => children.isNotEmpty;
}

class _SidebarItem extends ConsumerWidget {
  final _NavItem item;
  final bool collapsed;
  const _SidebarItem({required this.item, required this.collapsed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPeopleOpen = ref.watch(_peopleFlyoutOpenProvider);
    final path = GoRouterState.of(context).uri.path;
    // Loan Records (formerly Loan Applications) is the parent of Active Loans & In-Office — keep it
    // highlighted when the user is on those child routes (tabs moved into
    // Loan Records top pills, side-nav entries removed).
    final isLoanApplicationsParent =
        (item.route == RouteConstants.hmLoanApplications &&
            (path == RouteConstants.hmLoans ||
                path.startsWith('${RouteConstants.hmLoans}/') ||
                path == RouteConstants.hmInOffice ||
                path.startsWith('${RouteConstants.hmInOffice}/'))) ||
        (item.route == RouteConstants.empLoans &&
            (path == RouteConstants.empActiveLoans ||
                path.startsWith('${RouteConstants.empActiveLoans}/') ||
                path == RouteConstants.empInOffice ||
                path.startsWith('${RouteConstants.empInOffice}/')));
    // Collections now contains Payments as a tab (side-nav Payments removed)
    final isCollectionsParent = (item.route == RouteConstants.hmCollections &&
            (path == RouteConstants.hmPayments ||
                path.startsWith('${RouteConstants.hmPayments}/') ||
                path == RouteConstants.hmPenalties ||
                path.startsWith('${RouteConstants.hmPenalties}/') ||
                path == RouteConstants.hmPaymentDetails ||
                path.startsWith('${RouteConstants.hmPaymentDetails.replaceFirst('/:id', '')}/'))) ||
        (item.route == RouteConstants.empCollections &&
            (path == RouteConstants.empPayments ||
                path.startsWith('${RouteConstants.empPayments}/')));
    final baseActive = isLoanApplicationsParent ||
        isCollectionsParent ||
        (item.route.isNotEmpty &&
            (path == item.route || path.startsWith('${item.route}/')));
    final isActive = !isPeopleOpen && baseActive;

    return Tooltip(
      message: collapsed ? item.label : '',
      preferBelow: false,
      child: InkWell(
        onTap: item.route.isNotEmpty ? () => context.go(item.route) : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 14 : 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.gold.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 20,
                color: isActive ? AppColors.gold : Colors.white54,
              ),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? AppColors.gold : Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Expandable group tile for nested navigation (e.g. People -> Employees/Riders/Lenders).
class _SidebarGroup extends StatelessWidget {
  final _NavItem item;
  final bool collapsed;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onExpandSidebar;

  const _SidebarGroup({
    required this.item,
    required this.collapsed,
    required this.isExpanded,
    required this.onToggle,
    required this.onExpandSidebar,
  });

  bool _isActive(String path, String route) =>
      route.isNotEmpty && (path == route || path.startsWith('$route/'));

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final childActive = item.children.any((c) => _isActive(path, c.route));
    final parentActive = _isActive(path, item.route);
    // Parent is considered active if itself active OR any child active (so the group stays highlighted).
    final isActive = parentActive || childActive;

    // Collapsed sidebar: show only parent icon, tap expands the sidebar.
    if (collapsed) {
      return Tooltip(
        message: item.label,
        preferBelow: false,
        child: InkWell(
          onTap: onExpandSidebar,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.gold.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isActive
                  ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
                  : null,
            ),
            child: Row(
              children: [
                Icon(item.icon,
                    size: 20,
                    color: isActive ? AppColors.gold : Colors.white54),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // ── Parent row ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.gold.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isActive
                  ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
                  : null,
            ),
            child: Row(
              children: [
                // Main tappable area navigates to the parent route (e.g. /hm/all-users).
                Expanded(
                  child: InkWell(
                    onTap: item.route.isNotEmpty
                        ? () => context.go(item.route)
                        : onToggle,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(item.icon,
                              size: 20,
                              color: isActive
                                  ? AppColors.gold
                                  : Colors.white54),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isActive
                                    ? AppColors.gold
                                    : Colors.white70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Expand / collapse chevron (does NOT navigate).
                InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        size: 18,
                        color: isActive ? AppColors.gold : Colors.white54,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
        // ── Children ──
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: ClipRect(
            child: isExpanded
                ? Container(
                    margin: const EdgeInsets.only(
                        left: 16, right: 8, top: 2, bottom: 4),
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Colors.white12, width: 1),
                      ),
                    ),
                    child: Column(
                      children: item.children.map((child) {
                        final childIsActive = _isActive(path, child.route);
                        return Padding(
                          padding: const EdgeInsets.only(left: 8, top: 2),
                          child: InkWell(
                            onTap: child.route.isNotEmpty
                                ? () => context.go(child.route)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: childIsActive
                                    ? AppColors.gold.withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: childIsActive
                                    ? Border.all(
                                        color: AppColors.gold
                                            .withValues(alpha: 0.25))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(child.icon,
                                      size: 18,
                                      color: childIsActive
                                          ? AppColors.gold
                                          : Colors.white54),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      child.label,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: childIsActive
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: childIsActive
                                            ? AppColors.gold
                                            : Colors.white70,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (childIsActive)
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: AppColors.gold,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ),
      ],
    );
  }
}

/// Flyout dropdown - click to open, shows the 5 People items.
/// Clean blue panel like the sidebar (no white, no extra icons, no radius - box).
class _FlyoutNavGroup extends ConsumerStatefulWidget {
  final _NavItem item;
  final bool collapsed;
  final double sidebarWidth;
  const _FlyoutNavGroup({
    required this.item,
    required this.collapsed,
    required this.sidebarWidth,
  });
  @override
  ConsumerState<_FlyoutNavGroup> createState() => _FlyoutNavGroupState();
}

class _FlyoutNavGroupState extends ConsumerState<_FlyoutNavGroup> {
  final GlobalKey _tileKey = GlobalKey();
  OverlayEntry? _entry;
  final Object _tapGroupId = Object();

  bool _isActivePath(String path, String route) =>
      route.isNotEmpty && (path == route || path.startsWith('$route/'));

  void _showFlyout() {
    if (_entry != null) return;
    final box = _tileKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final overlay = Overlay.of(context);
    final pos = box.localToGlobal(Offset.zero);
    double left = widget.sidebarWidth + 6;
    double top = pos.dy - 2;
    const flyoutWidth = 200.0;
    final flyoutHeight = widget.item.children.length * 42.0 + 16.0;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    if (top + flyoutHeight > screenHeight - 12) {
      top = screenHeight - flyoutHeight - 12;
      if (top < 8) top = 8;
    }
    if (left + flyoutWidth > screenWidth - 12) {
      left = screenWidth - flyoutWidth - 12;
    }
    _entry = OverlayEntry(
      builder: (_) {
        final currentPath = GoRouterState.of(context).uri.path;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: TapRegion(
                groupId: _tapGroupId,
                onTapOutside: (_) => _hideFlyout(),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: flyoutWidth,
                    decoration: const BoxDecoration(
                      color: AppColors.deepNavy,
                      border: Border.fromBorderSide(BorderSide(color: Colors.white12)),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: widget.item.children.map((child) {
                        final childActive = _isActivePath(currentPath, child.route);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: InkWell(
                            onTap: () {
                              _hideFlyout();
                              if (child.route.isNotEmpty) context.go(child.route);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              decoration: BoxDecoration(
                                color: childActive
                                    ? AppColors.gold.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                border: childActive
                                    ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(child.icon,
                                      size: 18,
                                      color: childActive ? AppColors.gold : Colors.white70),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      child.label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: childActive ? FontWeight.w600 : FontWeight.w400,
                                        color: childActive ? AppColors.gold : Colors.white70,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
    ref.read(_peopleFlyoutOpenProvider.notifier).state = true;
    if (mounted) setState(() {});
  }

  void _hideFlyout() {
    _entry?.remove();
    _entry = null;
    ref.read(_peopleFlyoutOpenProvider.notifier).state = false;
    if (mounted) setState(() {});
  }

  void _toggleFlyout() {
    final isCurrentlyOpen = _entry != null;
    if (isCurrentlyOpen) {
      _hideFlyout();
    } else {
      // Select People (navigate to All Users) and open the box with 5 items
      if (widget.item.route.isNotEmpty) {
        final currentPath = GoRouterState.of(context).uri.path;
        if (currentPath != widget.item.route) {
          context.go(widget.item.route);
        }
      }
      _showFlyout();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shouldOpen = ref.read(_peopleFlyoutOpenProvider);
      if (shouldOpen && _entry == null) {
        _showFlyout();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final path = GoRouterState.of(context).uri.path;
    final isActive = _isActivePath(path, widget.item.route) ||
        widget.item.children.any((c) => _isActivePath(path, c.route));
    if (!isActive && _entry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _entry != null) _hideFlyout();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _FlyoutNavGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsed != widget.collapsed && _entry != null) {
      _hideFlyout();
    }
  }

  @override
  void deactivate() {
    _entry?.remove();
    _entry = null;
    super.deactivate();
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final isOpen = _entry != null || ref.watch(_peopleFlyoutOpenProvider);
    final childActive = widget.item.children.any((c) => _isActivePath(path, c.route));
    final parentActive = _isActivePath(path, widget.item.route);
    final isActive = isOpen || parentActive || childActive;
    if (widget.collapsed) {
      return TapRegion(
        groupId: _tapGroupId,
        child: Container(
          key: _tileKey,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Tooltip(
            message: widget.item.label,
            preferBelow: false,
            child: InkWell(
              onTap: _toggleFlyout,
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.gold.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isActive
                      ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
                      : null,
                ),
                child: Icon(widget.item.icon,
                    size: 20, color: isActive ? AppColors.gold : Colors.white54),
              ),
            ),
          ),
        ),
      );
    }
    return TapRegion(
      groupId: _tapGroupId,
      child: Container(
        key: _tileKey,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive ? Border.all(color: AppColors.gold.withValues(alpha: 0.3)) : null,
        ),
        child: InkWell(
          onTap: _toggleFlyout,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(widget.item.icon,
                    size: 20, color: isActive ? AppColors.gold : Colors.white54),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? AppColors.gold : Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedRotation(
                  turns: isOpen ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more,
                      size: 18, color: isActive ? AppColors.gold : Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

