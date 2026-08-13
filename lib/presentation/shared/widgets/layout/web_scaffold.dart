// lib/presentation/shared/widgets/layout/web_scaffold.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../providers/auth_state_provider.dart';

final _sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

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

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: Row(
        children: [
          RepaintBoundary(child: _Sidebar(collapsed: collapsed, role: role)),
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
                  child: Stack(
                    children: [
                      body,
                      if (floatingActionButton != null)
                        Positioned(
                          bottom: 24,
                          right: 24,
                          child: floatingActionButton!,
                        ),
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
              const unread = 0;
              final role = authState.role ?? '';
              void onNotificationTap() {
                if (role == AppConstants.roleHeadManager) {
                  context.go(RouteConstants.hmNotifications);
                } else if (role == AppConstants.roleEmployee) {
                  context.go(RouteConstants.empNotifications);
                }
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: onNotificationTap,
                    icon: const Icon(
                      Icons.notifications_outlined,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          '$unread',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
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
    final name = authState.user?.fullName ?? '';
    final initials = name.isNotEmpty
        ? name
            .trim()
            .split(' ')
            .map((p) => p.isNotEmpty ? p[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : 'U';

    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.gold.withValues(alpha: 0.2),
        child: Text(
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

class _Sidebar extends StatelessWidget {
  final bool collapsed;
  final String role;

  const _Sidebar({
    required this.collapsed,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final items = role == AppConstants.roleHeadManager
        ? _hmItems(context)
        : _empItems(context);
    final w = collapsed ? 68.0 : 240.0;

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
          _SidebarHeader(collapsed: collapsed),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: items
                  .map((item) => _SidebarItem(item: item, collapsed: collapsed))
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
          Icons.local_shipping_outlined,
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
          Icons.local_shipping_outlined,
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
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.7)),
            ),
            child: ClipOval(
              child: Image.asset(AssetConstants.logoJpg, fit: BoxFit.cover),
            ),
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
