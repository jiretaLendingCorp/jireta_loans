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
        _UserAvatar(authState: authState),
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
  const _UserAvatar({required this.authState});

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
    final initials = name.isNotEmpty
        ? name
            .trim()
            .split(' ')
            .map((p) => p.isNotEmpty ? p[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : 'U';
    final photoUrl =
        profileUser?.profilePhotoUrl ?? authState.user?.profilePhotoUrl;

    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ProfileAvatar(
        photoUrl: photoUrl,
        name: name,
        color: AppColors.deepNavy,
        radius: 18,
        borderColor: Colors.black,
        fallback: Text(
          initials,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.gold,
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.collapsed;
    final role = widget.role;
    final inDrawer = widget.inDrawer;
    final items = role == AppConstants.roleHeadManager
        ? _hmItems(context)
        : _empItems(context);
    final w = inDrawer ? double.infinity : (collapsed ? 68.0 : 240.0);

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
          _SidebarHeader(collapsed: inDrawer ? false : collapsed),
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: items
                  .map((item) => _SidebarItem(
                        item: item,
                        collapsed: inDrawer ? false : collapsed,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<_NavItem> _hmItems(BuildContext ctx) => [
        const _NavItem(
            Icons.dashboard_outlined, 'Dashboard', RouteConstants.hmDashboard),
        const _NavItem(
            Icons.group_outlined, 'All Users', RouteConstants.hmAllUsers),
        const _NavItem(
            Icons.people_outline, 'Employees', RouteConstants.hmEmployees),
        const _NavItem(
            Icons.delivery_dining_outlined, 'Riders', RouteConstants.hmRiders),
        const _NavItem(
            Icons.person_outline, 'Lenders', RouteConstants.hmLenders),
        const _NavItem(
          Icons.storefront_outlined,
          'In-Office Application',
          RouteConstants.hmInOffice,
        ),
        const _NavItem(
          Icons.description_outlined,
          'Loan Applications',
          RouteConstants.hmLoanApplications,
        ),
        const _NavItem(
          Icons.account_balance_wallet_outlined,
          'Active Loans',
          RouteConstants.hmLoans,
        ),
        const _NavItem(Icons.verified_user_outlined, 'Account Upgrade Review',
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
            Icons.payments_outlined, 'Payments', RouteConstants.hmPayments),
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
        const _NavItem(
            Icons.person_outline, 'Lenders', RouteConstants.empLenders),
        const _NavItem(
          Icons.delivery_dining_outlined,
          'Riders',
          RouteConstants.empRiders,
        ),
        const _NavItem(
          Icons.description_outlined,
          'Loan Applications',
          RouteConstants.empLoans,
        ),
        const _NavItem(
          Icons.account_balance_wallet_outlined,
          'Active Loans',
          RouteConstants.empActiveLoans,
        ),
        const _NavItem(
          Icons.storefront_outlined,
          'In-Office Application',
          RouteConstants.empInOffice,
        ),
        const _NavItem(Icons.verified_user_outlined, 'Account Upgrade Review',
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
        const _NavItem(
            Icons.payments_outlined, 'Payments', RouteConstants.empPayments),
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
  const _NavItem(this.icon, this.label, this.route);
}

class _SidebarItem extends StatelessWidget {
  final _NavItem item;
  final bool collapsed;
  const _SidebarItem({required this.item, required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final isActive = item.route.isNotEmpty &&
        (path == item.route || path.startsWith('${item.route}/'));

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
