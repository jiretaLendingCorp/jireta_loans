// lib/presentation/shared/widgets/notification_dropdown.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/notification_model.dart';
import '../../features/employee/notifications/providers/emp_notification_provider.dart';
import '../../features/head_manager/notifications/providers/hm_notification_provider.dart';
import '../providers/auth_state_provider.dart';
import 'notification_badge.dart';

/// Bell button used in the web header (desktop + mobile).
/// Tapping opens a dropdown panel with the latest notifications
/// instead of navigating straight to the full notification page.
class NotificationBellButton extends ConsumerStatefulWidget {
  final Color iconColor;
  final double iconSize;

  const NotificationBellButton({
    super.key,
    this.iconColor = AppColors.textSecondary,
    this.iconSize = 22,
  });

  @override
  ConsumerState<NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState extends ConsumerState<NotificationBellButton>
    with TickerProviderStateMixin {
  final GlobalKey _bellKey = GlobalKey();
  final Object _tapGroupId = Object();
  OverlayEntry? _entry;
  bool _closing = false;
  // Panel open/close animation — owned here so no GlobalKey<State> is needed.
  // (A typed GlobalKey on a private State class throws on web.)
  AnimationController? _panelCtrl;

  // Wiggle that plays when a NEW notification arrives (unread goes up).
  late final AnimationController _wiggleCtrl = AnimationController(
    duration: const Duration(milliseconds: 550),
    vsync: this,
  );
  late final Animation<double> _wiggle =
      TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.28), weight: 1),
        TweenSequenceItem(tween: Tween(begin: -0.28, end: 0.24), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 0.24, end: -0.16), weight: 1),
        TweenSequenceItem(tween: Tween(begin: -0.16, end: 0.1), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 0.1, end: 0.0), weight: 1),
      ]).animate(
        CurvedAnimation(parent: _wiggleCtrl, curve: Curves.easeInOut),
      );
  int _prevUnread = 0;
  bool _primed = false;

  @override
  void dispose() {
    _wiggleCtrl.dispose();
    _panelCtrl?.dispose();
    _removeEntrySync();
    super.dispose();
  }

  bool get _isOpen => _entry != null && !_closing;

  void _toggle() {
    if (_isOpen) {
      _hide();
    } else {
      _show();
    }
  }

  void _show() {
    if (_closing) {
      // A close animation is still running — drop it so a stale entry
      // never outlives this state, then open fresh.
      _closing = false;
      final stale = _entry;
      _entry = null;
      if (stale != null) _safeRemove(stale);
      _panelCtrl?.dispose();
      _panelCtrl = null;
    }
    if (_entry != null) return;
    final box = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final overlay = Overlay.of(context);
    final pos = box.localToGlobal(Offset.zero);
    final bellSize = box.size;

    // Dock the panel to the right edge (below the bell/avatar area).
    // Fixed margin so it always hugs the right side like a typical
    // notification dropdown, instead of floating mid-screen.
    const double right = 12;
    double top = pos.dy + bellSize.height + 10;
    // Clamp vertically (fallback: show below top bar).
    if (top < 56) top = 56;

    final panelCtrl = AnimationController(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
      vsync: this,
    );
    _panelCtrl = panelCtrl;

    _entry = OverlayEntry(
      builder: (overlayCtx) => Stack(
        children: [
          // Click-away layer (fades in with the panel).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hide,
              child: const _FadeInBackdrop(),
            ),
          ),
          Positioned(
            top: top,
            right: right,
            child: TapRegion(
              groupId: _tapGroupId,
              onTapOutside: (_) => _hide(),
              child: Material(
                color: Colors.transparent,
                child: _AnimatedDropdown(
                  controller: panelCtrl,
                  child: NotificationDropdownPanel(
                    onClose: _hide,
                    onViewAll: _handleViewAll,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
    if (mounted) setState(() {});
  }

  void _hide() {
    final entry = _entry;
    final panelCtrl = _panelCtrl;
    if (entry == null || _closing) return;
    if (panelCtrl == null) {
      _entry = null;
      _safeRemove(entry);
      if (mounted) setState(() {});
      return;
    }
    // Keep _entry set until the reverse animation finishes so
    // dispose/deactivate can always find and remove a live entry.
    _closing = true;
    if (mounted) setState(() {});
    panelCtrl.reverse().then((_) {
      _closing = false;
      if (identical(_entry, entry)) _entry = null;
      _safeRemove(entry);
      // Dispose only if it is still ours (a fresh _show may have replaced it).
      if (identical(_panelCtrl, panelCtrl)) _panelCtrl = null;
      panelCtrl.dispose();
      if (mounted) setState(() {});
    });
  }

  void _safeRemove(OverlayEntry entry) {
    try {
      entry.remove();
    } catch (_) {
      // Already detached — nothing to do.
    }
  }

  void _removeEntrySync() {
    final entry = _entry;
    _entry = null;
    final panelCtrl = _panelCtrl;
    _panelCtrl = null;
    panelCtrl?.dispose();
    if (entry == null) return;
    _safeRemove(entry);
  }

  void _handleViewAll() {
    final role = ref.read(authStateProvider).role ?? '';
    // Capture router before closing (overlay context gets disposed).
    final router = GoRouter.of(context);
    _hide();
    if (role == AppConstants.roleHeadManager) {
      router.go(RouteConstants.hmNotifications);
    } else if (role == AppConstants.roleEmployee) {
      router.go(RouteConstants.empNotifications);
    }
  }

  void _maybeWiggle(int unread) {
    if (!_primed) {
      _prevUnread = unread;
      _primed = true;
      return;
    }
    if (unread > _prevUnread) {
      _prevUnread = unread;
      // Restart the wiggle even if it is mid-flight.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _wiggleCtrl.forward(from: 0);
      });
    } else {
      _prevUnread = unread;
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authStateProvider).role ?? '';
    final unread = role == AppConstants.roleHeadManager
        ? ref.watch(hmNotificationProvider).unreadCount
        : role == AppConstants.roleEmployee
            ? ref.watch(empNotificationProvider).unreadCount
            : 0;
    _maybeWiggle(unread);

    return IconButton(
      key: _bellKey,
      onPressed: _toggle,
      tooltip: 'Notifications',
      // Pop the whole bell a touch when the panel opens.
      icon: AnimatedScale(
        scale: _isOpen ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AnimatedBuilder(
          animation: _wiggle,
          builder: (context, child) => Transform.rotate(
            angle: _wiggle.value,
            child: child,
          ),
          child: NotificationBadge(
            count: unread,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                _isOpen
                    ? Icons.notifications_rounded
                    : Icons.notifications_outlined,
                key: ValueKey<bool>(_isOpen),
                color: widget.iconColor,
                size: widget.iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades the click-away backdrop in on open.
class _FadeInBackdrop extends StatefulWidget {
  const _FadeInBackdrop();

  @override
  State<_FadeInBackdrop> createState() => _FadeInBackdropState();
}

class _FadeInBackdropState extends State<_FadeInBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    duration: const Duration(milliseconds: 180),
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
      child: Container(color: Colors.black.withValues(alpha: 0.04)),
    );
  }
}

/// Open/close animation for the dropdown panel:
/// fade + slide down a touch + pop from the top-right corner.
/// The [controller] is owned by the bell button (not by this widget),
/// so closing can reverse the animation before the overlay is removed.
class _AnimatedDropdown extends StatefulWidget {
  final AnimationController controller;
  final Widget child;

  const _AnimatedDropdown({
    required this.controller,
    required this.child,
  });

  @override
  State<_AnimatedDropdown> createState() => _AnimatedDropdownState();
}

class _AnimatedDropdownState extends State<_AnimatedDropdown> {
  late final Animation<double> _opacity = CurvedAnimation(
    parent: widget.controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero).animate(
        CurvedAnimation(
          parent: widget.controller,
          curve: Curves.easeOutCubic,
        ),
      );
  late final Animation<double> _scale =
      Tween<double>(begin: 0.95, end: 1.0).animate(
        CurvedAnimation(
          parent: widget.controller,
          curve: Curves.easeOutBack,
        ),
      );

  @override
  void initState() {
    super.initState();
    widget.controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Align(
          alignment: Alignment.topRight,
          child: ScaleTransition(
            scale: _scale,
            alignment: Alignment.topRight,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Staggered entrance for each list row: fade + rise, delayed by index.
class _StaggeredItem extends StatefulWidget {
  final int index;
  final Widget child;

  const _StaggeredItem({required this.index, required this.child});

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final delay = math.min(widget.index, 7) * 35;
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      opacity: _visible ? 1.0 : 0.0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        offset: _visible ? Offset.zero : const Offset(0, 0.25),
        child: widget.child,
      ),
    );
  }
}

/// The floating panel shown under the bell.
class NotificationDropdownPanel extends ConsumerWidget {
  final VoidCallback onClose;
  final VoidCallback onViewAll;

  const NotificationDropdownPanel({
    super.key,
    required this.onClose,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authStateProvider).role ?? '';
    final isHm = role == AppConstants.roleHeadManager;
    final isEmp = role == AppConstants.roleEmployee;

    final List<NotificationModel> notifications;
    final int unread;
    final bool isLoading;
    final String? error;
    final VoidCallback onRefresh;
    final void Function() onMarkAllRead;
    final void Function(String id) onMarkRead;

    if (isHm) {
      final state = ref.watch(hmNotificationProvider);
      notifications = state.notifications;
      unread = state.unreadCount;
      isLoading = state.isLoading;
      error = state.error;
      onRefresh = () =>
          ref.read(hmNotificationProvider.notifier).loadNotifications();
      onMarkAllRead =
          () => ref.read(hmNotificationProvider.notifier).markAllRead();
      onMarkRead = (id) =>
          ref.read(hmNotificationProvider.notifier).markRead(id);
    } else if (isEmp) {
      final state = ref.watch(empNotificationProvider);
      notifications = state.notifications;
      unread = state.unreadCount;
      isLoading = state.isLoading;
      error = state.error;
      onRefresh = () =>
          ref.read(empNotificationProvider.notifier).loadNotifications();
      onMarkAllRead =
          () => ref.read(empNotificationProvider.notifier).markAllRead();
      onMarkRead = (id) =>
          ref.read(empNotificationProvider.notifier).markRead(id: id);
    } else {
      notifications = const [];
      unread = 0;
      isLoading = false;
      error = null;
      onRefresh = () {};
      onMarkAllRead = () {};
      onMarkRead = (_) {};
    }

    // Show latest 7; full list lives on the View All page.
    final visible = notifications.length > 7
        ? notifications.sublist(0, 7)
        : notifications;

    return Container(
      width: MediaQuery.of(context).size.width < 392
          ? MediaQuery.of(context).size.width - 32
          : 360,
      constraints: const BoxConstraints(maxHeight: 460),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  ),
                  child: unread > 0
                      ? Container(
                          key: ValueKey<int>(unread),
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread new',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const SizedBox(key: ValueKey<String>('none')),
                ),
                const Spacer(),
                if (unread > 0)
                  TextButton(
                    onPressed: onMarkAllRead,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Mark all read',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.deepNavy,
                      ),
                    ),
                  ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isLoading
                      ? const Padding(
                          key: ValueKey<String>('loading'),
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          key: const ValueKey<String>('idle'),
                          onPressed: onRefresh,
                          tooltip: 'Refresh',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          // ── List ──
          Flexible(
            child: _buildList(
              context,
              isLoading: isLoading,
              error: error,
              visible: visible,
              totalCount: notifications.length,
              onMarkRead: onMarkRead,
              onRefresh: onRefresh,
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          // ── Footer ──
          _ViewAllFooter(onViewAll: onViewAll),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context, {
    required bool isLoading,
    required String? error,
    required List<NotificationModel> visible,
    required int totalCount,
    required void Function(String id) onMarkRead,
    required VoidCallback onRefresh,
  }) {
    if (isLoading && visible.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (error != null && visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 28,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 8),
            const Text(
              'Failed to load notifications',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRefresh, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (visible.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 30,
              color: AppColors.textTertiary,
            ),
            SizedBox(height: 8),
            Text(
              "You're all caught up",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'New notifications will appear here.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: visible.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
        itemBuilder: (_, i) {
          final n = visible[i];
          return _StaggeredItem(
            index: i,
            child: InkWell(
              onTap: n.isRead ? null : () => onMarkRead(n.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                color: n.isRead
                    ? Colors.transparent
                    : AppColors.deepNavy.withValues(alpha: 0.04),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.6, end: 1.0),
                      duration: Duration(
                        milliseconds: 260 + math.min(i, 7) * 35,
                      ),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _typeColor(n.type).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _typeIcon(n.type),
                          size: 17,
                          color: _typeColor(n.type),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  n.title.isEmpty ? 'Notification' : n.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: n.isRead
                                        ? FontWeight.w500
                                        : FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, animation) =>
                                    ScaleTransition(
                                      scale: animation,
                                      child: child,
                                    ),
                                child: !n.isRead
                                    ? Container(
                                        key: ValueKey<String>('dot-${n.id}'),
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(left: 6),
                                        decoration: const BoxDecoration(
                                          color: AppColors.error,
                                          shape: BoxShape.circle,
                                        ),
                                      )
                                    : const SizedBox(
                                        key: ValueKey<String>('no-dot'),
                                        width: 0,
                                      ),
                              ),
                            ],
                          ),
                          if (n.body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              n.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ],
                          const SizedBox(height: 3),
                          Text(
                            timeago.format(n.createdAt),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
      case 'ci':
        return Icons.search_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'loan':
        return AppColors.deepNavy;
      case 'payment':
        return AppColors.success;
      case 'account_upgrade':
        return AppColors.info;
      case 'collection':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }
}

/// Footer with a subtle arrow nudge on hover (web).
class _ViewAllFooter extends StatefulWidget {
  final VoidCallback onViewAll;

  const _ViewAllFooter({required this.onViewAll});

  @override
  State<_ViewAllFooter> createState() => _ViewAllFooterState();
}

class _ViewAllFooterState extends State<_ViewAllFooter> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onViewAll,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'View All Notifications',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                offset: _hovered ? const Offset(0.25, 0) : Offset.zero,
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: AppColors.deepNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
