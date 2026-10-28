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
import '../../../features/lender/profile/providers/lender_profile_provider.dart';
import '../../providers/auth_state_provider.dart';
import '../dialogs/confirmation_dialog.dart';
import '../dialogs/success_dialog.dart';
import '../notification_dropdown.dart';
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

/// Lapad kung saan nagsisimula ang desktop chrome: sidebar + top bar ang
/// ipinapakita (tingnan ang [WebScaffold]) imbes na ang mobile na app bar at
/// floating bottom nav. Ginagamit din ito ng `MobileScaffold` para sa desktop
/// layout ng lender role — isang breakpoint lang para sa buong app.
const double kDesktopBreakpoint = 900;

/// Logout flow na pinagsasaluhan ng avatar dropdown (HM / employee) at ng
/// "Log Out" na item sa sidebar ng lender: confirm modal → loading modal →
/// success modal → login page.
Future<void> performLogout(BuildContext context, WidgetRef ref) async {
  // Prevent double-tap while a logout is already running.
  if (ref.read(authStateProvider).isLoggingOut) return;
  // Capture the router BEFORE any async gap. Once logout clears the auth
  // state, the router's redirect immediately unmounts this dashboard subtree
  // (auto-navigate to /login) — using `context.go` afterwards would run on a
  // disposed context and can leave the app on a blank /login page (URL
  // changes, no widget builds).
  final router = GoRouter.of(context);
  // 1) Confirm modal muna: "Are you sure to logout?" — kaparehong shared
  // dialog ng mobile logout para theme-aware ang "No" (hindi ito mawala sa
  // dark mode gaya ng default na AlertDialog action).
  final confirmed = await showConfirmationDialog(
    context,
    // Walang heading — tanong lang at Yes/No na nasa gitna.
    title: '',
    message: 'Are you sure to logout?',
    confirmLabel: 'Yes',
    cancelLabel: 'No',
    isDangerous: true,
    centerText: true,
    showIcon: false,
    showDivider: false,
    width: 280,
  );
  if (confirmed != true || !context.mounted) return;
  // 2) Loading modal (non-dismissible) habang tumatakbo ang logout.
  // Hold the auto-redirect while the modals are up para hindi ma-yank ang
  // stack mid-modal (gaya sa mobile logout flow).
  AppConstants.suppressLogoutRedirect = true;
  if (context.mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 14),
              Text('Logging out…',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
  try {
    await ref.read(authProvider.notifier).logout();
  } catch (_) {
    // Tuloy pa rin sa success flow — naka-clear na ang session.
  } finally {
    AppConstants.suppressLogoutRedirect = false;
  }
  if (context.mounted) Navigator.pop(context); // close loading
  if (!context.mounted) return;
  // 3) Success modal — steady 2s, tapos diretso sa login.
  try {
    await SuccessDialog.showAutoDismiss(
      context,
      title: 'Successfully Logged Out',
      message: 'You have been logged out successfully.',
    );
  } catch (_) {}
  if (router.routeInformationProvider.value.uri.path !=
      RouteConstants.webLogin) {
    router.go(RouteConstants.webLogin);
  }
}

class WebScaffold extends ConsumerWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// Widget na ipinapakita sa UNANG bahagi ng top bar (bago ang sidebar
  /// toggle) — dito ipinapasa ng lender desktop layout ang back button ng mga
  /// detail screen. Walang epekto sa HM / employee screens (null ito sa kanila).
  final Widget? leading;

  /// Pinipilit ang role na gagamitin sa sidebar navigation. Kapag null, ang
  /// role ng naka-log in (auth state) ang batayan. Kailangan ito ng lender
  /// desktop shell para hindi mawala ang lender navigation kahit hindi pa
  /// nakumpirma ang role (hal. account upgrade / onboarding flow).
  final String? roleOverride;

  const WebScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.leading,
    this.roleOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(_sidebarCollapsedProvider);
    final authState = ref.watch(authStateProvider);
    final role = roleOverride ?? authState.role ?? '';
    // Ang rider ay may SARILING kulay ng sidebar (berde) — hindi navy — para
    // agad makilala ang role. Nananatiling navy ang HM / employee / lender.
    final isRider = role == AppConstants.roleRider;
    final sidebarColor =
        isRider ? AppColors.riderGreenDark : AppColors.deepNavy;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= kDesktopBreakpoint;

        if (isDesktop) {
          return Scaffold(
            backgroundColor: context.cPageBg,
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
                        leading: leading,
                        onMenuTap: () => ref
                            .read(_sidebarCollapsedProvider.notifier)
                            .state = !collapsed,
                        authState: authState,
                        // Ang role ng SHELL (kasama ang roleOverride) ang
                        // batayan ng chrome — hindi lang ang auth state.
                        role: role,
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
          backgroundColor: context.cPageBg,
          appBar: AppBar(
            backgroundColor: context.cPageBg,
            foregroundColor: context.cTextPrimary,
            elevation: 0,
            automaticallyImplyLeading: false,
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: Icon(Icons.menu, color: context.cTextSecondary),
                tooltip: 'Open Menu',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.cTextPrimary,
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
                      _MobileActions(authState: authState, role: role),
                    ],
                  ),
                ),
              ),
            ],
          ),
          drawer: Drawer(
            width: 240,
            backgroundColor: sidebarColor,
            elevation: 0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide.none,
            ),
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
  final String role;
  const _MobileActions({required this.authState, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const NotificationBellButton(),
        // Lender at rider: nasa drawer/sidebar na ang My Profile at Log Out
        // (tingnan ang `_SidebarAccountItem`), kaya hindi na ipinapakita ang
        // avatar.
        if (role != AppConstants.roleLender &&
            role != AppConstants.roleRider)
          _UserAvatar(authState: authState, showName: false),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final VoidCallback onMenuTap;
  final AuthState authState;

  /// Role na ginagamit ng shell (auth state o `roleOverride`).
  final String role;

  const _TopBar({
    required this.title,
    this.actions,
    this.leading,
    required this.onMenuTap,
    required this.authState,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: context.cSurface,
        border: Border(bottom: BorderSide(color: context.cBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (leading != null) leading!,
          IconButton(
            onPressed: onMenuTap,
            icon: Icon(Icons.menu, color: context.cTextSecondary),
            tooltip: 'Toggle Sidebar',
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.cTextPrimary,
            ),
          ),
          const Spacer(),
          if (actions != null) ...actions!,
          const SizedBox(width: 8),
          NotificationBellButton(iconColor: context.cTextSecondary),
          const SizedBox(width: 4),
          // Nakatago na ang identity (avatar + pangalan + role) sa lender at
          // rider: nasa SIDEBAR na ang My Profile at Log Out, kaya duplikado at
          // walang laman na dropdown lang ito. Ang HM / employee ay hindi
          // apektado.
          if (role != AppConstants.roleLender &&
              role != AppConstants.roleRider)
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
    } else if (role == AppConstants.roleLender) {
      profileUser = ref.watch(lenderProfileProvider).user;
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

    // Identity row (avatar + pangalan + role) — ito ang ipinapakita ng top bar.
    final identity = Row(
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
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.cTextPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (roleLabel.isNotEmpty)
                  Text(
                    roleLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: context.cTextTertiary,
                      letterSpacing: 0.4,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(width: 4),
        Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: context.cTextSecondary,
        ),
      ],
    );

    // Ang lender ay may "My Profile" at "Log Out" na sa SIDEBAR — wala nang
    // natitirang laman ang dropdown para sa kanila, kaya plain display na lang
    // ang avatar (hindi na clickable). Ang HM / employee ay dropdown pa rin.
    if (authState.role == AppConstants.roleLender) return identity;

    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: identity,
      onSelected: (val) async {
        if (val == 'profile') {
          final role = authState.role;
          if (role == AppConstants.roleHeadManager) {
            context.go(RouteConstants.hmProfile);
          } else if (role == AppConstants.roleEmployee) {
            context.go(RouteConstants.empProfile);
          } else if (role == AppConstants.roleLender) {
            context.go(RouteConstants.lenderProfile);
          }
        } else if (val == 'settings') {
          context.go(RouteConstants.hmSettings);
        } else if (val == 'logout') {
          await performLogout(context, ref);
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
        if (authState.role == AppConstants.roleHeadManager)
          const PopupMenuItem(
            value: 'settings',
            child: Row(
              children: [
                Icon(Icons.settings_outlined, size: 18),
                SizedBox(width: 10),
                Text('Settings'),
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

  /// Whether text labels may render. Kept false until the expand animation
  /// finishes — flipping to full content while the panel is still narrow
  /// overflows (the fixed icon + gap alone exceed the animating width).
  late bool _showLabels;

  @override
  void initState() {
    super.initState();
    _showLabels = widget.inDrawer ? true : !widget.collapsed;
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
    final items = _itemsForRole(role);
    final w = inDrawer ? double.infinity : (collapsed ? 68.0 : 240.0);
    final path = GoRouterState.of(context).uri.path;
    final expandedGroups = ref.watch(_sidebarExpandedGroupsProvider);
    // Hide labels the moment a collapse starts (icon-only always fits);
    // reveal them only after the expand animation completes.
    ref.listen<bool>(_sidebarCollapsedProvider, (prev, next) {
      if (next && _showLabels && mounted) {
        setState(() => _showLabels = false);
      }
    });
    final showText = inDrawer ? true : (_showLabels && !collapsed);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: w,
      onEnd: () {
        if (mounted &&
            !inDrawer &&
            !ref.read(_sidebarCollapsedProvider) &&
            !_showLabels) {
          setState(() => _showLabels = true);
        }
      },
      // Flat panel — no border, no shadow/outline on the edge. Navy para sa HM
      // / employee / lender, at BERDE para sa rider (role color nila).
      decoration: BoxDecoration(
        color: role == AppConstants.roleRider ? null : AppColors.deepNavy,
        gradient: role == AppConstants.roleRider
            ? const LinearGradient(
                colors: [AppColors.riderGreenDark, AppColors.riderGreen],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : null,
      ),
      child: Column(
        children: [
          // Compact look follows the label flag (not the raw toggle) so the
          // animating panel never overflows.
          _SidebarHeader(collapsed: !showText),
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
                    showText: showText,
                    sidebarWidth: collapsed ? 68.0 : 240.0,
                  );
                }
                return _SidebarItem(
                  item: item,
                  collapsed: !showText,
                  green: role == AppConstants.roleRider,
                );
              }).toList(),
            ),
          ),
          // ── Account items (LENDER / RIDER) ────────────────────────────
          // Nasa SIDEBAR na ang My Profile at Log Out — hindi na dropdown sa
          // avatar ng top bar. Nakapin sa ibaba, hiwalay sa mga pangunahing
          // section ng app.
          if (role == AppConstants.roleLender ||
              role == AppConstants.roleRider) ...[
            const Divider(height: 1, thickness: 1, color: Colors.white12),
            const SizedBox(height: 8),
            _SidebarAccountItem(
              icon: Icons.person_outlined,
              label: 'My Profile',
              collapsed: !showText,
              green: role == AppConstants.roleRider,
              isActive: role == AppConstants.roleRider
                  ? (path == RouteConstants.riderProfile ||
                      path.startsWith('${RouteConstants.riderProfile}/'))
                  : (path == RouteConstants.lenderProfile ||
                      path.startsWith('${RouteConstants.lenderProfile}/')),
              onTap: () => context.go(role == AppConstants.roleRider
                  ? RouteConstants.riderProfile
                  : RouteConstants.lenderProfile),
            ),
            _SidebarAccountItem(
              icon: Icons.logout,
              label: 'Log Out',
              collapsed: !showText,
              green: role == AppConstants.roleRider,
              onTap: () => performLogout(context, ref),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

}

/// Mga nav item ng bawat role — isang pinagmumulan lang ito para sa sidebar
/// (HM / employee) at sa header nav bar (lender).
List<_NavItem> _itemsForRole(String role) {
  if (role == AppConstants.roleHeadManager) return _hmItems();
  if (role == AppConstants.roleLender) return _lenderItems();
  if (role == AppConstants.roleRider) return _riderItems();
  return _empItems();
}

/// Mga section ng RIDER role para sa sidebar — Home, Collections, Deliveries,
/// CI Tasks at History. Ang Profile at Log Out ay nasa account section sa
/// ibaba ng sidebar (tingnan ang `_SidebarAccountItem`).
List<_NavItem> _riderItems() => const [
      _NavItem(Icons.home_outlined, 'Home', RouteConstants.riderDashboard),
      _NavItem(Icons.payments_outlined, 'Collections',
          RouteConstants.riderCollections),
      // Cash Deliveries (rider_delivery disbursements) — dati'y maabot lang
      // mula sa dashboard card, ngayon may sariling sidebar entry.
      _NavItem(Icons.delivery_dining_outlined, 'Deliveries',
          RouteConstants.riderDisbursements),
      _NavItem(Icons.search_outlined, 'CI Tasks', RouteConstants.riderCi),
      _NavItem(Icons.history_outlined, 'History', RouteConstants.riderHistory),
    ];

List<_NavItem> _hmItems() => [
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
            _NavItem(Icons.admin_panel_settings_outlined, 'Head Managers',
                RouteConstants.hmHeadManagers),
            _NavItem(
                Icons.badge_outlined, 'Employees', RouteConstants.hmEmployees),
            _NavItem(Icons.delivery_dining_outlined, 'Riders',
                RouteConstants.hmRiders),
            _NavItem(
                Icons.person_outline, 'Lendees', RouteConstants.hmLenders),
            _NavItem(
                Icons.archive_outlined, 'Archived', RouteConstants.hmArchived),
          ],
        ),
        const _NavItem(Icons.verified_user_outlined, 'Lendee Account Upgrade',
            RouteConstants.hmAccountUpgrade),
        const _NavItem(
          Icons.description_outlined,
          'Loan Records',
          RouteConstants.hmLoanApplications,
        ),
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
        // Read-only monitoring ng bawat rider — accounts, expected vs
        // confirmed collections, overdue at remaining balances.
        const _NavItem(
          Icons.insights_outlined,
          'Rider Monitoring',
          RouteConstants.hmRiderMonitoring,
        ),
        const _NavItem(
            Icons.assessment_outlined, 'Reports', RouteConstants.hmReports),
        const _NavItem(
            Icons.history_outlined, 'Audit Logs', RouteConstants.hmAudit),
      ];

List<_NavItem> _empItems() => [
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
                Icons.person_outline, 'Lendees', RouteConstants.empLenders),
            _NavItem(Icons.delivery_dining_outlined, 'Riders',
                RouteConstants.empRiders),
          ],
        ),
        const _NavItem(Icons.verified_user_outlined, 'Lendee Account Upgrade',
            RouteConstants.empAccountUpgrade),
        const _NavItem(
          Icons.description_outlined,
          'Loan Records',
          RouteConstants.empLoans,
        ),
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
        // Read-only rider monitoring — kapareho ng HM entry, para makita ng
        // employee ang expected vs confirmed collections ng bawat rider.
        const _NavItem(
          Icons.insights_outlined,
          'Rider Monitoring',
          RouteConstants.empRiderMonitoring,
        ),
      ];

/// Mga section ng LENDER role para sa sidebar — TATLONG items lang ito
/// (Dashboard, Payments, Transactions), kapareho ng laman ng mobile bottom nav.
/// Ang ibang lender sections (Loans, Collections, Documents, Account Upgrade,
/// Profile) ay hindi nakalista rito: ang My Profile at Log Out ay nasa account
/// section sa ibaba ng sidebar (tingnan ang `_SidebarAccountItem`).
List<_NavItem> _lenderItems() => const [
      _NavItem(Icons.dashboard_outlined, 'Dashboard',
          RouteConstants.lenderDashboard),
      _NavItem(
          Icons.payments_outlined, 'Payments', RouteConstants.lenderPayments),
      _NavItem(Icons.receipt_long_outlined, 'Transactions',
          RouteConstants.lenderPaymentHistory),
    ];

/// Ang "Payments" ng lender ay sumasakop din sa mga payment sub-screen (GCash,
/// office cash, payment method at resibo) — hindi ito dapat mawalan ng
/// highlight kapag nandoon ang user.
bool _isLenderPaymentsItemActive(_NavItem item, String path) =>
    item.route == RouteConstants.lenderPayments &&
    (path.startsWith(RouteConstants.lenderPaymentMethod) ||
        path.startsWith(RouteConstants.lenderPayViaGcash) ||
        path.startsWith(RouteConstants.lenderOfficePayment) ||
        path.startsWith(RouteConstants.lenderPaymentReceipt
            .replaceFirst('/:id', '')));

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

  /// Rider sidebar = BERDE, kaya puti ang active na text/icon (hindi gold —
  /// lubog ang gold sa green kaya hindi mabasa ang naka-select na item).
  final bool green;

  const _SidebarItem({
    required this.item,
    required this.collapsed,
    this.green = false,
  });

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
    // ── Lender ──
    // Ang "Payments" ng lender ay sumasakop din sa mga payment sub-screen
    // (method, GCash, office cash, resibo) — ang "Transactions" ang history lang.
    final isLenderPaymentsParent = _isLenderPaymentsItemActive(item, path);
    final baseActive = isLoanApplicationsParent ||
        isCollectionsParent ||
        isLenderPaymentsParent ||
        (item.route.isNotEmpty &&
            (path == item.route || path.startsWith('${item.route}/')));
    final isActive = !isPeopleOpen && baseActive;
    // Active accent: gold sa navy sidebar, PUTI sa berdeng rider sidebar.
    final activeFg = green ? Colors.white : AppColors.gold;
    final activeBg = green
        ? Colors.white.withValues(alpha: 0.18)
        : AppColors.gold.withValues(alpha: 0.15);
    final activeBorder = green
        ? Colors.white.withValues(alpha: 0.36)
        : AppColors.gold.withValues(alpha: 0.3);

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
            color: isActive ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive ? Border.all(color: activeBorder) : null,
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 20,
                color: isActive ? activeFg : Colors.white54,
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
                      color: isActive ? activeFg : Colors.white70,
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

/// Item sa ibaba ng sidebar para sa account actions ng LENDER (My Profile at
/// Log Out). Hindi ito kasama sa `_itemsForRole` dahil hindi ito navigation
/// section ng app — pares lang ito ng account action na nakapin sa ibaba, at
/// ginaya ang hitsura ng `_SidebarItem` para pantay ang alignment.
class _SidebarAccountItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool collapsed;
  final bool isActive;

  /// Hindi ito navigation item — kaya walang route: ang tap ay direktang
  /// tumatakbo ng action (hal. logout) o `context.go(...)` mula sa caller.
  final VoidCallback onTap;

  /// Rider sidebar = BERDE — puti ang active accent para mabasa (hindi gold).
  final bool green;

  const _SidebarAccountItem({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.isActive = false,
    this.green = false,
  });

  @override
  Widget build(BuildContext context) {
    // Kapareho ng kulay ng ibang sidebar item (puti) — hindi pula: ordinaryong
    // nav item ang Log Out, hindi babala.
    final Color activeFg = green ? Colors.white : AppColors.gold;
    final Color fg = isActive ? activeFg : Colors.white70;
    final Color iconColor = isActive ? activeFg : Colors.white54;

    return Tooltip(
      message: collapsed ? label : '',
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 14 : 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? (green
                    ? Colors.white.withValues(alpha: 0.18)
                    : AppColors.gold.withValues(alpha: 0.15))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(
                    color: green
                        ? Colors.white.withValues(alpha: 0.36)
                        : AppColors.gold.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: fg,
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
  final bool showText;
  final double sidebarWidth;
  const _FlyoutNavGroup({
    required this.item,
    required this.collapsed,
    required this.showText,
    required this.sidebarWidth,
  });
  @override
  ConsumerState<_FlyoutNavGroup> createState() => _FlyoutNavGroupState();
}

class _FlyoutNavGroupState extends ConsumerState<_FlyoutNavGroup> {
  final GlobalKey _tileKey = GlobalKey();
  final GlobalKey<_AnimatedFlyoutState> _menuKey =
      GlobalKey<_AnimatedFlyoutState>();
  OverlayEntry? _entry;
  bool _closing = false;
  final Object _tapGroupId = Object();

  bool _isActivePath(String path, String route) =>
      route.isNotEmpty && (path == route || path.startsWith('$route/'));

  void _showFlyout() {
    if (_closing) {
      // A close animation is still running — drop its overlay now so a
      // defunct entry never outlives this State, then open fresh.
      _closing = false;
      final stale = _entry;
      _entry = null;
      if (stale != null) _safeRemove(stale);
    }
    if (_entry != null) return;
    final box = _tileKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final overlay = Overlay.of(context);
    final pos = box.localToGlobal(Offset.zero);
    double left = widget.sidebarWidth + 6;
    double top = pos.dy - 2;
    const flyoutWidth = 208.0;
    final flyoutHeight = widget.item.children.length * 46.0 + 24.0;
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
                  child: _AnimatedFlyout(
                    key: _menuKey,
                    child: Container(
                      width: flyoutWidth,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.deepNavy,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(4, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.item.children
                            .asMap()
                            .entries
                            .map((entry) {
                          final i = entry.key;
                          final child = entry.value;
                          final childActive =
                              _isActivePath(currentPath, child.route);
                          return Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                            child: InkWell(
                              onTap: () {
                                _hideFlyout();
                                if (child.route.isNotEmpty) {
                                  context.go(child.route);
                                }
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: childActive
                                      ? AppColors.gold
                                          .withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: childActive
                                      ? Border.all(
                                          color: AppColors.gold.withValues(
                                              alpha: 0.3))
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Icon(child.icon,
                                        size: 18,
                                        color: childActive
                                            ? AppColors.gold
                                            : Colors.white70),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        child.label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: childActive
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: childActive
                                              ? AppColors.gold
                                              : Colors.white70,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (childActive)
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
    final entry = _entry;
    if (entry == null || _closing) return;
    ref.read(_peopleFlyoutOpenProvider.notifier).state = false;
    final panel = _menuKey.currentState;
    if (panel == null) {
      _entry = null;
      _safeRemove(entry);
    } else {
      // Keep _entry set until the overlay is actually detached so
      // deactivate/dispose can always find and remove a live entry.
      _closing = true;
      panel.reverse().then((_) {
        _closing = false;
        if (identical(_entry, entry)) _entry = null;
        _safeRemove(entry);
      });
    }
    if (mounted) setState(() {});
  }

  void _safeRemove(OverlayEntry entry) {
    try {
      entry.remove();
    } catch (_) {
      // Already detached (e.g. route disposed first) — nothing to do.
    }
  }

  void _toggleFlyout() {
    final isCurrentlyOpen = _entry != null && !_closing;
    if (isCurrentlyOpen) {
      _hideFlyout();
    } else {
      // _showFlyout also cancels a close animation still running.
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
    final entry = _entry;
    _entry = null;
    _closing = false;
    if (entry != null) _safeRemove(entry);
    super.deactivate();
  }

  @override
  void dispose() {
    final entry = _entry;
    _entry = null;
    if (entry != null) _safeRemove(entry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final isOpen = _entry != null || ref.watch(_peopleFlyoutOpenProvider);
    final childActive = widget.item.children.any((c) => _isActivePath(path, c.route));
    final parentActive = _isActivePath(path, widget.item.route);
    final isActive = isOpen || parentActive || childActive;
    if (!widget.showText) {
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

/// Fade + slide-in wrapper for the People flyout menu so it animates open
/// (and closed) instead of popping in instantly.
class _AnimatedFlyout extends StatefulWidget {
  final Widget child;

  const _AnimatedFlyout({super.key, required this.child});

  @override
  State<_AnimatedFlyout> createState() => _AnimatedFlyoutState();
}

class _AnimatedFlyoutState extends State<_AnimatedFlyout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    duration: const Duration(milliseconds: 200),
    vsync: this,
  );
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(-0.08, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  Future<void> reverse() async {
    await _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

