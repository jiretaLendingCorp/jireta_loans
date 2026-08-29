// lib/presentation/shared/widgets/navigation/collapsible_sidebar.dart

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class SidebarItem {
  final IconData icon;
  final String label;
  final String route;
  final bool hasNotification;
  final List<SidebarItem> children;

  const SidebarItem({
    required this.icon,
    required this.label,
    required this.route,
    this.hasNotification = false,
    this.children = const [],
  });

  bool get isGroup => children.isNotEmpty;
}

class CollapsibleSidebar extends StatefulWidget {
  final bool collapsed;
  final List<SidebarItem> items;
  final String activeRoute;
  final VoidCallback onToggle;
  final Function(String) onNavigate;
  final Widget? header;

  const CollapsibleSidebar({
    super.key,
    required this.collapsed,
    required this.items,
    required this.activeRoute,
    required this.onToggle,
    required this.onNavigate,
    this.header,
  });

  @override
  State<CollapsibleSidebar> createState() => _CollapsibleSidebarState();
}

class _CollapsibleSidebarState extends State<CollapsibleSidebar> {
  bool _isActive(String route) =>
      route.isNotEmpty && widget.activeRoute.startsWith(route);

  bool _isGroupActive(SidebarItem group) =>
      _isActive(group.route) ||
      group.children.any((c) => _isActive(c.route));

  @override
  Widget build(BuildContext context) {
    final sidebarWidth = widget.collapsed ? 64.0 : 240.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.deepNavy,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          if (widget.header != null) widget.header!,
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: widget.items.map((item) {
                if (item.isGroup) {
                  final isActive = _isGroupActive(item);
                  // Flyout dropdown: shows overlay panel to the right with All Users etc.
                  return _CollapsibleFlyoutTile(
                    item: item,
                    isActive: isActive,
                    collapsed: widget.collapsed,
                    activeRoute: widget.activeRoute,
                    sidebarWidth: sidebarWidth,
                    onNavigate: widget.onNavigate,
                  );
                }
                final isActive = _isActive(item.route);
                return _SidebarTile(
                  item: item,
                  isActive: isActive,
                  collapsed: widget.collapsed,
                  onTap: () => widget.onNavigate(item.route),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Flyout dropdown - click to open, clean blue like sidebar.
class _CollapsibleFlyoutTile extends StatefulWidget {
  final SidebarItem item;
  final bool isActive;
  final bool collapsed;
  final String activeRoute;
  final double sidebarWidth;
  final Function(String) onNavigate;
  const _CollapsibleFlyoutTile({
    required this.item,
    required this.isActive,
    required this.collapsed,
    required this.activeRoute,
    required this.sidebarWidth,
    required this.onNavigate,
  });
  @override
  State<_CollapsibleFlyoutTile> createState() => _CollapsibleFlyoutTileState();
}

class _CollapsibleFlyoutTileState extends State<_CollapsibleFlyoutTile> {
  final GlobalKey _tileKey = GlobalKey();
  OverlayEntry? _entry;
  final Object _tapGroupId = Object();

  bool _isActive(String route) => route.isNotEmpty && widget.activeRoute.startsWith(route);

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
      builder: (_) => Stack(
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
                  decoration: BoxDecoration(
                    color: AppColors.deepNavy,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: Colors.white12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(2, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.item.children.map((child) {
                      final childActive = _isActive(child.route);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: InkWell(
                          onTap: () {
                            _hideFlyout();
                            widget.onNavigate(child.route);
                          },
                          borderRadius: BorderRadius.zero,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: childActive
                                  ? AppColors.gold.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.zero,
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
      ),
    );
    overlay.insert(_entry!);
    if (mounted) setState(() {});
  }

  void _hideFlyout() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _toggleFlyout() {
    if (_entry != null) {
      _hideFlyout();
    } else {
      _showFlyout();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.isActive && _entry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _entry != null) _hideFlyout();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _CollapsibleFlyoutTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsed != widget.collapsed && _entry != null) {
      _hideFlyout();
    }
    if (!widget.isActive && _entry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _entry != null) _hideFlyout();
      });
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
    final isOpen = _entry != null;
    if (widget.collapsed) {
      final bg = widget.isActive ? AppColors.sidebarActive : Colors.transparent;
      return TapRegion(
        groupId: _tapGroupId,
        child: Container(
          key: _tileKey,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Tooltip(
            message: widget.item.label,
            child: GestureDetector(
              onTap: () {
                if (widget.item.route.isNotEmpty) widget.onNavigate(widget.item.route);
                _toggleFlyout();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.zero,
                  border: widget.isActive
                      ? const Border(left: BorderSide(color: AppColors.gold, width: 3))
                      : null,
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(widget.item.icon,
                            color: widget.isActive
                                ? AppColors.gold
                                : AppColors.textOnDark.withValues(alpha: 0.7),
                            size: 20),
                        if (widget.item.hasNotification)
                          Positioned(
                            top: -3,
                            right: -3,
                            child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: AppColors.error, shape: BoxShape.circle)),
                          ),
                      ],
                    ),
                  ],
                ),
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
          color: widget.isActive
              ? AppColors.gold.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.zero,
          border: widget.isActive
              ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
              : null,
        ),
        child: InkWell(
          onTap: () {
            if (widget.item.route.isNotEmpty) widget.onNavigate(widget.item.route);
            _toggleFlyout();
          },
          borderRadius: BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(widget.item.icon,
                    size: 20,
                    color: widget.isActive
                        ? AppColors.gold
                        : AppColors.textOnDark.withValues(alpha: 0.7)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.item.label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                          color: widget.isActive
                              ? AppColors.gold
                              : AppColors.textOnDark.withValues(alpha: 0.85)),
                      overflow: TextOverflow.ellipsis),
                ),
                AnimatedRotation(
                  turns: isOpen ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more,
                      size: 18,
                      color: widget.isActive
                          ? AppColors.gold
                          : AppColors.textOnDark.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



class _SidebarGroupTile extends StatefulWidget {
  final SidebarItem item;
  final bool isActive;
  final bool isExpanded;
  final bool collapsed;
  final String activeRoute;
  final VoidCallback onToggle;
  final Function(String) onNavigate;

  const _SidebarGroupTile({
    required this.item,
    required this.isActive,
    required this.isExpanded,
    required this.collapsed,
    required this.activeRoute,
    required this.onToggle,
    required this.onNavigate,
  });

  @override
  State<_SidebarGroupTile> createState() => _SidebarGroupTileState();
}

class _SidebarGroupTileState extends State<_SidebarGroupTile> {
  bool _hovered = false;

  bool _isActive(String route) =>
      route.isNotEmpty && widget.activeRoute.startsWith(route);

  @override
  Widget build(BuildContext context) {
    // Collapsed: show only parent icon; tap expands the sidebar first.
    if (widget.collapsed) {
      final bg = widget.isActive
          ? AppColors.sidebarActive
          : _hovered
              ? AppColors.sidebarItem
              : Colors.transparent;
      final iconColor = widget.isActive
          ? AppColors.gold
          : AppColors.textOnDark.withValues(alpha: 0.7);
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onToggle,
          child: Tooltip(
            message: widget.item.label,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.zero,
                border: widget.isActive
                    ? const Border(
                        left: BorderSide(color: AppColors.gold, width: 3),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(widget.item.icon, color: iconColor, size: 20),
                      if (widget.item.hasNotification)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final bg = widget.isActive
        ? AppColors.gold.withValues(alpha: 0.15)
        : _hovered
            ? AppColors.sidebarItem
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        children: [
          // Parent row
          GestureDetector(
            onTap: widget.item.route.isNotEmpty
                ? () => widget.onNavigate(widget.item.route)
                : widget.onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.zero,
                border: widget.isActive
                    ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(widget.item.icon,
                                  color: widget.isActive
                                      ? AppColors.gold
                                      : AppColors.textOnDark
                                          .withValues(alpha: 0.7),
                                  size: 20),
                              if (widget.item.hasNotification)
                                Positioned(
                                  top: -3,
                                  right: -3,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColors.error,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.item.label,
                              style: TextStyle(
                                color: widget.isActive
                                    ? AppColors.gold
                                    : AppColors.textOnDark
                                        .withValues(alpha: 0.85),
                                fontSize: 13,
                                fontWeight: widget.isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Chevron toggle (doesn't navigate, only expands)
                  InkWell(
                    onTap: widget.onToggle,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AnimatedRotation(
                        turns: widget.isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more,
                          size: 18,
                          color: widget.isActive
                              ? AppColors.gold
                              : AppColors.textOnDark.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          // Children
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: ClipRect(
              child: widget.isExpanded
                  ? Container(
                      margin: const EdgeInsets.only(
                          left: 16, right: 8, top: 2, bottom: 4),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: Colors.white12, width: 1),
                        ),
                      ),
                      child: Column(
                        children: widget.item.children.map((child) {
                          final childActive = _isActive(child.route);
                          return Padding(
                            padding: const EdgeInsets.only(left: 8, top: 2),
                            child: _ChildTile(
                              item: child,
                              isActive: childActive,
                              onTap: () => widget.onNavigate(child.route),
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildTile extends StatefulWidget {
  final SidebarItem item;
  final bool isActive;
  final VoidCallback onTap;
  const _ChildTile(
      {required this.item, required this.isActive, required this.onTap});

  @override
  State<_ChildTile> createState() => _ChildTileState();
}

class _ChildTileState extends State<_ChildTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final bg = widget.isActive
        ? AppColors.gold.withValues(alpha: 0.12)
        : _hovered
            ? AppColors.sidebarItem.withValues(alpha: 0.5)
            : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.zero,
            border: widget.isActive
                ? Border.all(color: AppColors.gold.withValues(alpha: 0.25))
                : null,
          ),
          child: Row(
            children: [
              Icon(widget.item.icon,
                  size: 18,
                  color: widget.isActive
                      ? AppColors.gold
                      : AppColors.textOnDark.withValues(alpha: 0.7)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.w400,
                    color: widget.isActive
                        ? AppColors.gold
                        : AppColors.textOnDark.withValues(alpha: 0.85),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.isActive)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                ),
              if (widget.item.hasNotification && !widget.isActive)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  final SidebarItem item;
  final bool isActive;
  final bool collapsed;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.isActive,
    required this.collapsed,
    required this.onTap,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isActive
        ? AppColors.sidebarActive
        : _hovered
            ? AppColors.sidebarItem
            : Colors.transparent;

    final iconColor = widget.isActive
        ? AppColors.gold
        : AppColors.textOnDark.withValues(alpha: 0.7);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: widget.collapsed ? 12 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.zero,
            border: widget.isActive
                ? const Border(
                    left: BorderSide(color: AppColors.gold, width: 3),
                  )
                : null,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(widget.item.icon, color: iconColor, size: 20),
                  if (widget.item.hasNotification)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              if (!widget.collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      color: widget.isActive
                          ? AppColors.gold
                          : AppColors.textOnDark.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight:
                          widget.isActive ? FontWeight.w600 : FontWeight.w400,
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
