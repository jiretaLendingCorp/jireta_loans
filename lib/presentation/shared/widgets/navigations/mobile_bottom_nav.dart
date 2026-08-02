// lib/presentation/shared/widgets/navigation/mobile_bottom_nav.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class MobileNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int? badgeCount;

  const MobileNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount,
  });
}

class MobileBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<MobileNavItem> items;
  final Function(int) onTap;
  final Color accentColor;

  const MobileBottomNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            children: items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final isActive = idx == currentIndex;
              return Expanded(
                child: _NavItem(
                  item: item,
                  isActive: isActive,
                  accentColor: accentColor,
                  onTap: () => onTap(idx),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final MobileNavItem item;
  final bool isActive;
  final Color accentColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.item,
    required this.isActive,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward().then((_) => _ctrl.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scale,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? widget.accentColor.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.isActive ? widget.item.activeIcon : widget.item.icon,
                    color: widget.isActive
                        ? widget.accentColor
                        : AppColors.textTertiary,
                    size: 22,
                  ),
                ),
                if ((widget.item.badgeCount ?? 0) > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(
                          minWidth: 16, minHeight: 16),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        widget.item.badgeCount! > 99
                            ? '99+'
                            : '${widget.item.badgeCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 10,
                color: widget.isActive
                    ? widget.accentColor
                    : AppColors.textTertiary,
                fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(widget.item.label),
            ),
          ],
        ),
      ),
    );
  }
}
