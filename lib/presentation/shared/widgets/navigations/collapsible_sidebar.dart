// lib/presentation/shared/widgets/navigation/collapsible_sidebar.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class SidebarItem {
  final IconData icon;
  final String label;
  final String route;
  final bool hasNotification;

  const SidebarItem({
    required this.icon,
    required this.label,
    required this.route,
    this.hasNotification = false,
  });
}

class CollapsibleSidebar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: collapsed ? 64 : 240,
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
          if (header != null) header!,
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: items.map((item) {
                final isActive = activeRoute.startsWith(item.route);
                return _SidebarTile(
                  item: item,
                  isActive: isActive,
                  collapsed: collapsed,
                  onTap: () => onNavigate(item.route),
                );
              }).toList(),
            ),
          ),
        ],
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
            borderRadius: BorderRadius.circular(8),
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
