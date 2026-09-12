// lib/presentation/shared/widgets/month_filter_dropdown.dart
// Single date filter — monthly + exact date sa isang box.
// Editable any month/year (year arrows + month grid), notification-style
// animation (fade + slide + scale) at redesigned rounded panel.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Reusable monthly / exact-date filter na gaya ng notification dropdown:
/// - isang box lang sa top bar (tipid sa space)
/// - editable kahit anong month/year via year navigator + month grid
/// - animated open/close + staggered month cells
class MonthFilterDropdown extends StatefulWidget {
  /// Currently selected month in `YYYY-MM` format.
  final String selectedMonth;

  /// Currently selected exact date in `YYYY-MM-DD` format, or null.
  final String? selectedDate;

  /// Called when a month cell is tapped.
  final ValueChanged<String> onMonthSelected;

  /// Called when "Exact date..." row is tapped.
  final VoidCallback onExactDateTap;

  /// Called when the X / "Back to monthly" is tapped. Null hides clear UI.
  final VoidCallback? onClearDate;

  /// Formats `YYYY-MM` -> display label (e.g. `Sep 2026`).
  final String Function(String yyyyMm) monthLabel;

  const MonthFilterDropdown({
    super.key,
    required this.selectedMonth,
    required this.selectedDate,
    required this.onMonthSelected,
    required this.onExactDateTap,
    this.onClearDate,
    required this.monthLabel,
  });

  /// Default `Sep 2026` style label (same as dashboards).
  static String defaultMonthLabel(String yyyyMm) {
    const mNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final parts = yyyyMm.split('-');
    if (parts.length != 2) return yyyyMm;
    final m = int.tryParse(parts[1]) ?? 1;
    if (m < 1 || m > 12) return yyyyMm;
    return '${mNames[m - 1]} ${parts[0]}';
  }

  @override
  State<MonthFilterDropdown> createState() => _MonthFilterDropdownState();
}

class _MonthFilterDropdownState extends State<MonthFilterDropdown>
    with TickerProviderStateMixin {
  final GlobalKey _btnKey = GlobalKey();
  final Object _tapGroupId = Object();
  OverlayEntry? _entry;
  bool _closing = false;
  AnimationController? _panelCtrl;

  bool get _isOpen => _entry != null && !_closing;

  @override
  void dispose() {
    _panelCtrl?.dispose();
    _removeEntrySync();
    super.dispose();
  }

  void _toggle() {
    if (_isOpen) {
      _hide();
    } else {
      _show();
    }
  }

  void _show() {
    if (_closing) {
      _closing = false;
      final stale = _entry;
      _entry = null;
      if (stale != null) _safeRemove(stale);
      _panelCtrl?.dispose();
      _panelCtrl = null;
    }
    if (_entry != null) return;
    final box = _btnKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final overlay = Overlay.of(context);
    final pos = box.localToGlobal(Offset.zero);
    final btnSize = box.size;

    final panelCtrl = AnimationController(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
      vsync: this,
    );
    _panelCtrl = panelCtrl;

    _entry = OverlayEntry(
      builder: (overlayCtx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hide,
              child: const _FadeInBackdrop(),
            ),
          ),
          Positioned(
            top: pos.dy + btnSize.height + 8,
            // Align panel's right edge with the button's right edge.
            left: (pos.dx + btnSize.width - _panelWidth).clamp(
              8.0,
              (MediaQuery.of(overlayCtx).size.width - _panelWidth - 8)
                  .clamp(8.0, double.infinity),
            ),
            child: TapRegion(
              groupId: _tapGroupId,
              onTapOutside: (_) => _hide(),
              child: Material(
                color: Colors.transparent,
                child: _AnimatedDropdown(
                  controller: panelCtrl,
                  child: _MonthPanel(
                    selectedMonth: widget.selectedMonth,
                    selectedDate: widget.selectedDate,
                    monthLabel: widget.monthLabel,
                    onMonthSelected: (m) {
                      _hide();
                      widget.onMonthSelected(m);
                    },
                    onExactDateTap: () {
                      _hide();
                      widget.onExactDateTap();
                    },
                    onClearDate: widget.selectedDate != null
                        ? () {
                            _hide();
                            widget.onClearDate?.call();
                          }
                        : null,
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
    _closing = true;
    if (mounted) setState(() {});
    panelCtrl.reverse().then((_) {
      _closing = false;
      if (identical(_entry, entry)) _entry = null;
      _safeRemove(entry);
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

  static const double _panelWidth = 264;

  @override
  Widget build(BuildContext context) {
    final label = widget.selectedDate ?? widget.monthLabel(widget.selectedMonth);
    final hasExact = widget.selectedDate != null;
    return Container(
      key: _btnKey,
      height: 38,
      decoration: BoxDecoration(
        // Clean minimal — walang boxy border, subtle lang pag open/active
        color: _isOpen
            ? AppColors.deepNavy.withValues(alpha: 0.06)
            : hasExact
                ? AppColors.deepNavy.withValues(alpha: 0.06)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Text(
                      label,
                      key: ValueKey<String>(label),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    hasExact
                        ? Icons.event_rounded
                        : Icons.calendar_month_rounded,
                    size: 17,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasExact && widget.onClearDate != null)
            InkWell(
              onTap: widget.onClearDate,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.only(right: 8, left: 2),
                child: Icon(Icons.close_rounded,
                    size: 15, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Redesigned floating panel — gaya ng notification dropdown:
/// rounded 12, border, shadow, header + editable year + month grid.
class _MonthPanel extends StatefulWidget {
  final String selectedMonth;
  final String? selectedDate;
  final String Function(String) monthLabel;
  final ValueChanged<String> onMonthSelected;
  final VoidCallback onExactDateTap;
  final VoidCallback? onClearDate;

  const _MonthPanel({
    required this.selectedMonth,
    required this.selectedDate,
    required this.monthLabel,
    required this.onMonthSelected,
    required this.onExactDateTap,
    this.onClearDate,
  });

  @override
  State<_MonthPanel> createState() => _MonthPanelState();
}

class _MonthPanelState extends State<_MonthPanel> {
  static const _mShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  late int _viewYear;

  @override
  void initState() {
    super.initState();
    _viewYear = int.tryParse(widget.selectedMonth.split('-').first) ??
        DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final selParts = widget.selectedMonth.split('-');
    final selYear = int.tryParse(selParts.firstOrNull ?? '');
    final selMonth = int.tryParse(selParts.length > 1 ? selParts[1] : '');

    return Container(
      width: 264,
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
          // ── Header: MONTHLY + editable year navigator ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
            child: Row(
              children: [
                const Text(
                  'MONTHLY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                _YearBtn(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => setState(() => _viewYear--),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '$_viewYear',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.deepNavy,
                    ),
                  ),
                ),
                _YearBtn(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => setState(() => _viewYear++),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          // ── Month grid (3x4) — kahit anong month puwedeng piliin ──
          Padding(
            padding: const EdgeInsets.all(10),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                mainAxisExtent: 34,
              ),
              itemCount: 12,
              itemBuilder: (_, i) {
                final m = i + 1;
                final key =
                    '$_viewYear-${m.toString().padLeft(2, '0')}';
                final isSel = widget.selectedDate == null &&
                    selYear == _viewYear &&
                    selMonth == m;
                return _StaggeredItem(
                  index: i,
                  child: InkWell(
                    onTap: () => widget.onMonthSelected(key),
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSel
                            ? AppColors.deepNavy
                            : AppColors.deepNavy.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSel
                              ? AppColors.deepNavy
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        _mShort[i],
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              isSel ? FontWeight.w800 : FontWeight.w600,
                          color: isSel
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          // ── Exact date row ──
          _StaggeredItem(
            index: 12,
            child: InkWell(
              onTap: widget.onExactDateTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: widget.selectedDate != null
                            ? AppColors.deepNavy
                            : AppColors.deepNavy
                                .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.event_rounded,
                        size: 15,
                        color: widget.selectedDate != null
                            ? Colors.white
                            : AppColors.deepNavy,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.selectedDate ?? 'Exact date...',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (widget.selectedDate != null &&
                        widget.onClearDate != null)
                      InkWell(
                        onTap: widget.onClearDate,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded,
                              size: 15,
                              color: AppColors.textSecondary),
                        ),
                      )
                    else
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppColors.textTertiary,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _YearBtn({required this.icon, required this.onTap});

  @override
  State<_YearBtn> createState() => _YearBtnState();
}

class _YearBtnState extends State<_YearBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover
                ? AppColors.deepNavy.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon,
              size: 18, color: AppColors.deepNavy),
        ),
      ),
    );
  }
}

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

/// Same open/close animation as notification dropdown:
/// fade + slide down + pop from top.
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

/// Staggered entrance per item — gaya ng notification list rows.
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
    final delay = (widget.index > 12 ? 12 : widget.index) * 25;
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
