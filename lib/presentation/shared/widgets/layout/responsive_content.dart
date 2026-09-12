// lib/presentation/shared/widgets/layout/responsive_content.dart
//
// Responsive helpers for the desktop-style list screens. These screens are
// built with fixed multi-column Rows (search toolbar + premium tables) that
// overflow on narrow/mobile viewports. The widgets below keep the exact
// desktop layout at wide widths and switch to a mobile-friendly layout
// (horizontal scroll, or stacked cards) below a breakpoint, so nothing ever
// renders a RenderFlex overflow error.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Wraps a desktop-style table so it never overflows on narrow screens.
///
/// The table keeps at least [minWidth] and scrolls horizontally when the
/// viewport is smaller. On wide screens it fills the available width exactly,
/// so the desktop layout is unchanged.
class ResponsiveTableScroll extends StatelessWidget {
  final double minWidth;
  final Widget child;

  const ResponsiveTableScroll({
    super.key,
    required this.minWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWidth = math.max(constraints.maxWidth, minWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // A fixed SizedBox (not ConstrainedBox(minWidth:)) is required here:
          // the horizontal scroll view gives the child an unbounded max width,
          // and the table rows are built from Row + Expanded columns. Expanded
          // needs a bounded max width, otherwise layout throws
          // "RenderFlex children have non-zero flex but incoming width
          // constraints are unbounded" and the whole table disappears.
          child: SizedBox(width: targetWidth, child: child),
        );
      },
    );
  }
}

/// Wraps the standard list toolbar (`search field + trailing filter chips`)
/// so it never overflows on narrow screens.
///
/// On wide screens it renders `Expanded(search) + trailing` exactly like the
/// previous inline Row. Below [breakpoint] it stays one row: the search
/// shrinks (Expanded) and the trailing filters keep their compact size at
/// the end, so nothing wraps to a second line and nothing is cut off.
class ResponsiveSearchToolbar extends StatelessWidget {
  final Widget searchField;

  /// Fixed-width widgets shown after the search field (date filter, results
  /// chip, action dropdown, …). A 12px gap is inserted between them.
  final List<Widget> trailing;

  /// Below this available width the toolbar switches to the compact,
  /// horizontally scrollable layout.
  final double breakpoint;

  /// Width given to the search field in the compact layout.
  final double compactSearchWidth;

  const ResponsiveSearchToolbar({
    super.key,
    required this.searchField,
    this.trailing = const [],
    this.breakpoint = 640,
    this.compactSearchWidth = 240,
  });

  List<Widget> _trailingWithGaps({double gap = 12}) {
    if (trailing.isEmpty) return const [];
    return [
      for (int i = 0; i < trailing.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        trailing[i],
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          // Mobile: ISANG ROW LANG — search flexible, filters compact sa dulo.
          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 8),
              ..._trailingWithGaps(gap: 8),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 12),
            ..._trailingWithGaps(),
          ],
        );
      },
    );
  }
}

// ─────────────────────────── ResponsiveListCard ───────────────────────────
//
// Renders a desktop-style table on wide screens (identical to the hand-written
// Row + Expanded tables these screens used) and switches to stacked, tappable
// cards below [minTableWidth] so every field and action stays visible without
// horizontal scrolling on mobile.

/// Visual style of the desktop table.
enum ResponsiveListVariant {
  /// White card, radius 16, F8F9FB header with bottom border, FDFDFD zebra
  /// rows (used by the "premium" tables: Loan Records, CI, Account Upgrade…).
  premium,

  /// Theme `Card`-like look: surfaceVariant header + Divider, surfaceVariant
  /// zebra rows (used by Riders, All Users, Payments, Penalties…).
  card,
}

/// One desktop table column. [label] is reused as the field label on the
/// mobile card layout; [icon] only renders in the premium header style.
class ResponsiveCol {
  final String label;
  final IconData? icon;
  final int flex;
  final bool alignEnd;

  const ResponsiveCol(this.label, {this.icon, this.flex = 1, this.alignEnd = false});
}

/// One table row. [cells] maps 1:1 to [ResponsiveListCard.columns]; [actions]
/// renders in the trailing action column on desktop and as a full-width
/// section at the bottom of the mobile card. [onTap] / [expanded] support
/// tappable expandable rows (audit-log style).
class ResponsiveRow {
  final List<Widget> cells;
  final Widget? actions;
  final VoidCallback? onTap;
  final Widget? expanded;

  const ResponsiveRow({required this.cells, this.actions, this.onTap, this.expanded});
}

/// Optional trailing column for row actions. On desktop it takes a fixed
/// [width] or a [flex] slot; [alignment] aligns the row content inside it.
class ResponsiveActionsCol {
  final String label;
  final IconData? icon;

  /// Custom header content replacing the label (e.g. the "New Walk-in" button
  /// in the In-Office table). Also shown above the cards on mobile.
  final Widget? headerWidget;
  final double? width;
  final int? flex;
  final Alignment? alignment;

  /// Right-aligns the header label (desktop).
  final bool alignEnd;

  const ResponsiveActionsCol({
    this.label = 'Action',
    this.icon = Icons.bolt_outlined,
    this.headerWidget,
    this.width,
    this.flex,
    this.alignment,
    this.alignEnd = false,
  });
}

class ResponsiveListCard extends StatelessWidget {
  /// Table width on desktop; below this the widget renders stacked cards.
  final double minTableWidth;
  final List<ResponsiveCol> columns;
  final List<ResponsiveRow> rows;
  final ResponsiveActionsCol? actionsCol;
  final ResponsiveListVariant variant;

  // Desktop table overrides (kept identical to each screen's original code).
  final double? rowHeight;
  final EdgeInsets rowPadding;
  final EdgeInsets headerPadding;
  final CrossAxisAlignment rowCrossAxisAlignment;
  final Border? rowBorder;
  final TextStyle? headerTextStyle;
  final double? radius;
  final Border? outerBorder;
  final List<BoxShadow>? outerShadow;
  final Color? headerColor;

  const ResponsiveListCard({
    super.key,
    required this.minTableWidth,
    required this.columns,
    required this.rows,
    this.actionsCol,
    this.variant = ResponsiveListVariant.premium,
    this.rowHeight,
    this.rowPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.rowCrossAxisAlignment = CrossAxisAlignment.center,
    this.rowBorder,
    this.headerTextStyle,
    this.radius,
    this.outerBorder,
    this.outerShadow,
    this.headerColor,
  });

  static const _premiumHeaderStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );

  static const _cardHeaderStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: AppColors.textSecondary,
  );

  TextStyle get _headerStyle =>
      headerTextStyle ?? (variant == ResponsiveListVariant.premium ? _premiumHeaderStyle : _cardHeaderStyle);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minTableWidth) return _buildMobile();
        return _buildDesktop();
      },
    );
  }

  // ── Desktop table (identical to the original hand-written layout) ──

  Widget _buildDesktop() {
    final header = Container(
      padding: headerPadding,
      decoration: BoxDecoration(
        color: headerColor ??
            (variant == ResponsiveListVariant.premium
                ? const Color(0xFFF8F9FB)
                : AppColors.surfaceVariant),
        border: variant == ResponsiveListVariant.premium
            ? const Border(bottom: BorderSide(color: AppColors.border))
            : null,
      ),
      child: Row(
        children: [
          for (final col in columns)
            Expanded(flex: col.flex, child: _desktopLabel(col)),
          if (actionsCol != null) _desktopActionsHeader(),
        ],
      ),
    );

    final body = Column(
      children: [
        header,
        if (variant == ResponsiveListVariant.card) const Divider(height: 1),
        for (var i = 0; i < rows.length; i++) _desktopRow(rows[i], i),
      ],
    );

    final effectiveRadius = radius ?? (variant == ResponsiveListVariant.premium ? 16.0 : 12.0);
    final effectiveBorder = outerBorder ?? Border.all(color: AppColors.border);
    final effectiveShadow = outerShadow ??
        (variant == ResponsiveListVariant.premium
            ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 14, offset: Offset(0, 4))]
            : null);

    return ResponsiveTableScroll(
      minWidth: minTableWidth,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(effectiveRadius),
          border: effectiveBorder,
          boxShadow: effectiveShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: body,
      ),
    );
  }

  Widget _desktopLabel(ResponsiveCol col) {
    if (variant == ResponsiveListVariant.premium) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (col.icon != null) ...[
            Icon(col.icon, size: 12, color: AppColors.textTertiary),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              col.label.toUpperCase(),
              style: _headerStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return Text(
      col.label,
      style: _headerStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _desktopActionsHeader() {
    final col = actionsCol!;
    final Widget content = col.headerWidget ??
        (variant == ResponsiveListVariant.premium
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (col.icon != null) ...[
                    Icon(col.icon, size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      col.label.toUpperCase(),
                      style: _headerStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Text(
                col.label,
                style: _headerStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: col.alignEnd ? TextAlign.end : TextAlign.start,
              ));

    final Widget aligned = col.alignEnd
        ? Align(alignment: Alignment.centerRight, child: content)
        : (col.headerWidget != null && col.alignment != null
            ? Align(alignment: col.alignment!, child: content)
            : content);

    if (col.width != null) return SizedBox(width: col.width, child: aligned);
    return Expanded(flex: col.flex ?? 1, child: aligned);
  }

  Widget _desktopRow(ResponsiveRow row, int index) {
    final isEven = index.isEven;
    final oddColor = variant == ResponsiveListVariant.premium
        ? const Color(0xFFFDFDFD)
        : AppColors.surfaceVariant.withValues(alpha: 0.3);
    final border = rowBorder ??
        (variant == ResponsiveListVariant.premium
            ? const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))
            : null);

    Widget content = Container(
      height: rowHeight,
      padding: rowPadding,
      decoration: BoxDecoration(color: isEven ? Colors.white : oddColor, border: border),
      child: Row(
        crossAxisAlignment: rowCrossAxisAlignment,
        children: [
          for (var i = 0; i < columns.length; i++)
            Expanded(flex: columns[i].flex, child: row.cells[i]),
          if (actionsCol != null) _desktopActionsSlot(row.actions),
        ],
      ),
    );

    if (row.onTap != null) content = InkWell(onTap: row.onTap, child: content);
    if (row.expanded != null) return Column(children: [content, row.expanded!]);
    return content;
  }

  Widget _desktopActionsSlot(Widget? actions) {
    final col = actionsCol!;
    final a = actions ?? const SizedBox.shrink();
    final content = col.alignment != null ? Align(alignment: col.alignment!, child: a) : a;
    if (col.width != null) return SizedBox(width: col.width, child: content);
    return Expanded(flex: col.flex ?? 1, child: content);
  }

  // ── Mobile cards (every field + action visible, no horizontal scroll) ──

  /// Width of the label column on mobile: wide enough for the longest label
  /// in this card, plus a small buffer so the text never wraps or clips.
  /// Every value then starts at the exact same x position (aligned
  /// pantay-pantay) while still sitting right next to the ":".
  double _labelColumnWidth() {
    final painter = TextPainter(textDirection: TextDirection.ltr);
    var maxWidth = 0.0;
    for (final col in columns) {
      painter.text = TextSpan(
        text: '${col.label.toUpperCase()}:',
        style: _premiumHeaderStyle,
      );
      painter.layout();
      maxWidth = math.max(maxWidth, painter.width);
    }
    painter.dispose();
    // Small buffer: TextPainter measurement can be a fraction of a pixel
    // narrower than the real render, which would otherwise force a wrap.
    return maxWidth + 4;
  }

  Widget _buildMobile() {
    final labelWidth = _labelColumnWidth();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (actionsCol?.headerWidget != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: actionsCol!.headerWidget,
            ),
          ),
        for (final row in rows) _mobileCard(row, labelWidth),
      ],
    );
  }

  Widget _mobileCard(ResponsiveRow row, double labelWidth) {
    Widget card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < columns.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _mobileField(columns[i], row.cells[i], labelWidth),
            ),
          if (row.actions != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: Color(0xFFF0F0F0)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: row.actions,
              ),
            ),
          ],
        ],
      ),
    );

    if (row.onTap != null) {
      card = InkWell(
        onTap: row.onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      );
    }
    if (row.expanded != null) return Column(children: [card, row.expanded!]);
    return card;
  }

  /// Mobile key-value row: "LABEL:" on the left, value right after it.
  /// [labelWidth] is the widest label in the card, so every value starts at
  /// the exact same x position (aligned pantay-pantay) and, for the longest
  /// label, sits right next to the ":".
  Widget _mobileField(ResponsiveCol col, Widget cell, double labelWidth) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: _mobileLabel(col),
        ),
        // Konting gap lang between the ":" and the value — data sits just a
        // little to the right of the colon.
        const SizedBox(width: 28),
        Expanded(
          child: cell,
        ),
      ],
    );
  }

  Widget _mobileLabel(ResponsiveCol col) {
    // softWrap: false guarantees the label NEVER breaks onto a second line
    // (e.g. "LENDER" / "& LOAN:"). The column is sized to the longest
    // label + buffer, so the full text also never gets cut off.
    return Text(
      '${col.label.toUpperCase()}:',
      style: _premiumHeaderStyle,
      softWrap: false,
    );
  }
}