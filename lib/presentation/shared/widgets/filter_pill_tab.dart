// lib/presentation/shared/widgets/filter_pill_tab.dart
//
// Shared clean filter pill tab used by the list screens (Loan Records, CI,
// Collections, Account Upgrade — HM + Employee). Rounded stadium shape,
// comfortable padding, navy + gold when active.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class FilterTabDef {
  final String key;
  final String label;
  final IconData icon;

  const FilterTabDef(this.key, this.label, this.icon);
}

class FilterPillTab extends StatelessWidget {
  final FilterTabDef def;
  final bool active;
  final VoidCallback onTap;

  const FilterPillTab({
    super.key,
    required this.def,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        // Fixed height so every pill (and the Pipeline dropdown beside
        // them) renders at exactly the same height.
        height: 36,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.deepNavy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.deepNavy : AppColors.border,
            width: active ? 1.2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.deepNavy.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              def.icon,
              size: 14,
              color: active ? AppColors.gold : AppColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              def.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dropdown-style tab button with an overlay menu. Tapping the button opens a
/// wide menu BELOW it (never covering the button itself); options render as
/// full-width centered bars — navy + gold for the selected one, white for
/// the rest. Tapping an option or anywhere outside closes the menu.
class FilterTabBar extends StatefulWidget {
  final String dropdownLabel;
  final List<FilterTabDef> dropdownOptions;
  final String? dropdownValue;
  final ValueChanged<String> onDropdownChanged;
  final List<Widget> pills;

  const FilterTabBar({
    super.key,
    required this.dropdownLabel,
    required this.dropdownOptions,
    required this.dropdownValue,
    required this.onDropdownChanged,
    this.pills = const [],
  });

  @override
  State<FilterTabBar> createState() => _FilterTabBarState();
}

class _FilterTabBarState extends State<FilterTabBar> {
  final GlobalKey _buttonKey = GlobalKey();
  final GlobalKey<_AnimatedMenuState> _menuKey =
      GlobalKey<_AnimatedMenuState>();
  OverlayEntry? _entry;
  bool _closing = false;

  bool get _open => _entry != null;

  @override
  void didUpdateWidget(covariant FilterTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-close when the selection changes elsewhere (e.g. a pill tap).
    if (_entry != null &&
        oldWidget.dropdownValue != widget.dropdownValue) {
      _hideMenu();
    }
  }

  void _toggleMenu() {
    if (_entry != null && !_closing) {
      _hideMenu();
    } else {
      _showMenu(); // also cancels a close animation still running
    }
  }

  void _showMenu() {
    if (_closing) {
      // A close animation is still running — drop its overlay now so a
      // defunct entry never outlives this State, then open fresh.
      _closing = false;
      final stale = _entry;
      _entry = null;
      if (stale != null) _safeRemove(stale);
    }
    if (_entry != null) return;
    final buttonBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final barBox = context.findRenderObject() as RenderBox?;
    if (buttonBox == null || barBox == null || !mounted) return;

    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    final screenH = media.size.height;
    final buttonPos = buttonBox.localToGlobal(Offset.zero);
    final barPos = barBox.localToGlobal(Offset.zero);

    // Compact menu: a bit wider than the button (capped), never full-width.
    // Sized from the button + screen — never collapses, never overflows.
    const margin = 12.0;
    var left = barPos.dx;
    if (left < margin) left = margin;
    var menuWidth =
        math.min(math.max(buttonBox.size.width + 24, 190.0), 260.0);
    if (left + menuWidth > screenW - margin) {
      left = screenW - margin - menuWidth;
      if (left < margin) {
        left = margin;
        menuWidth = screenW - margin * 2;
      }
    }

    // Open BELOW the button so the navy button itself is never covered.
    const itemH = 36.0;
    const gap = 8.0;
    const pad = 8.0;
    final n = widget.dropdownOptions.length;
    final menuH = pad * 2 + n * itemH + (n - 1) * gap;
    var top = buttonPos.dy + buttonBox.size.height + 8;
    if (top + menuH > screenH - 12) {
      top = buttonPos.dy - 8 - menuH;
      if (top < 8) top = 8;
    }

    // Snapshot — the overlay does not rebuild with the parent.
    final options = widget.dropdownOptions;
    final value = widget.dropdownValue;

    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Transparent barrier: blocks page scroll behind, closes on tap.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: Material(
              color: Colors.transparent,
              // No panel box — just the option buttons floating on their own.
              child: _AnimatedMenu(
                key: _menuKey,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < options.length; i++) ...[
                        if (i > 0) const SizedBox(height: gap),
                        _MenuOption(
                          def: options[i],
                          active: options[i].key == value,
                          onTap: () {
                            _hideMenu();
                            widget.onDropdownChanged(options[i].key);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  void _hideMenu() {
    final entry = _entry;
    if (entry == null || _closing) return;
    final panel = _menuKey.currentState;
    if (panel == null) {
      _entry = null;
      _safeRemove(entry);
      if (mounted) setState(() {});
      return;
    }
    // Keep _entry set until the overlay is actually detached so
    // deactivate/dispose can always find and remove a live entry.
    _closing = true;
    panel.reverse().then((_) {
      _closing = false;
      if (identical(_entry, entry)) _entry = null;
      _safeRemove(entry);
      if (mounted) setState(() {});
    });
  }

  void _safeRemove(OverlayEntry entry) {
    try {
      entry.remove();
    } catch (_) {
      // Already detached (e.g. route disposed first) — nothing to do.
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
    FilterTabDef? selected;
    for (final t in widget.dropdownOptions) {
      if (t.key == widget.dropdownValue) {
        selected = t;
        break;
      }
    }
    final isActive = selected != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                key: _buttonKey,
                onTap: _toggleMenu,
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 36,
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color:
                        isActive ? AppColors.deepNavy : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive
                          ? AppColors.deepNavy
                          : AppColors.border,
                      width: isActive ? 1.2 : 1,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppColors.deepNavy
                                  .withValues(alpha: 0.18),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selected?.icon ?? Icons.filter_list_rounded,
                        size: 14,
                        color: isActive
                            ? AppColors.gold
                            : AppColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        selected?.label ?? widget.dropdownLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 16,
                          color: isActive
                              ? Colors.white
                              : AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.pills.isNotEmpty) const SizedBox(width: 8),
              ...widget.pills,
            ],
          ),
        ),
      ],
    );
  }
}

/// One wide menu option: full-width centered bar — navy + gold when selected,
/// white with border otherwise.
class _MenuOption extends StatelessWidget {
  final FilterTabDef def;
  final bool active;
  final VoidCallback onTap;

  const _MenuOption({
    required this.def,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 36,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.deepNavy : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? AppColors.deepNavy : AppColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              def.icon,
              size: 16,
              color: active ? AppColors.gold : AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              def.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fade + slide-down wrapper for the dropdown menu so opening (and closing)
/// is animated instead of popping in instantly.
class _AnimatedMenu extends StatefulWidget {
  final Widget child;

  const _AnimatedMenu({super.key, required this.child});

  @override
  State<_AnimatedMenu> createState() => _AnimatedMenuState();
}

class _AnimatedMenuState extends State<_AnimatedMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    duration: const Duration(milliseconds: 220),
    vsync: this,
  );
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.08),
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
