// lib/presentation/shared/widgets/tables/enterprise_table.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class TableColumn {
  final String key;
  final String label;
  final double? width;
  final bool sortable;
  final TextAlign align;

  const TableColumn({
    required this.key,
    required this.label,
    this.width,
    this.sortable = true,
    this.align = TextAlign.left,
  });
}

class EnterpriseTable extends StatefulWidget {
  final List<TableColumn> columns;
  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic> row)? onRowTap;
  final List<Widget> Function(Map<String, dynamic> row)? rowActions;
  final Widget Function(String key, dynamic value)? cellBuilder;
  final bool isLoading;
  final Widget? emptyWidget;

  const EnterpriseTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.rowActions,
    this.cellBuilder,
    this.isLoading = false,
    this.emptyWidget,
  });

  @override
  State<EnterpriseTable> createState() => _EnterpriseTableState();
}

class _EnterpriseTableState extends State<EnterpriseTable> {
  String? _sortKey;
  bool _sortAsc = true;
  int? _hoveredIndex;

  List<Map<String, dynamic>> get _sorted {
    if (_sortKey == null) return widget.rows;
    final copy = [...widget.rows];
    copy.sort((a, b) {
      final av = a[_sortKey!];
      final bv = b[_sortKey!];
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      int cmp;
      if (av is num && bv is num) {
        cmp = av.compareTo(bv);
      } else {
        cmp = av.toString().compareTo(bv.toString());
      }
      return _sortAsc ? cmp : -cmp;
    });
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) return _buildSkeleton();
    if (widget.rows.isEmpty) {
      return widget.emptyWidget ?? _buildEmpty();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildRows()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          ...widget.columns.map((col) => _HeaderCell(
                column: col,
                isSorted: _sortKey == col.key,
                isAsc: _sortAsc,
                onSort: col.sortable
                    ? () => setState(() {
                          if (_sortKey == col.key) {
                            _sortAsc = !_sortAsc;
                          } else {
                            _sortKey = col.key;
                            _sortAsc = true;
                          }
                        })
                    : null,
              )),
          if (widget.rowActions != null) const SizedBox(width: 120),
        ],
      ),
    );
  }

  Widget _buildRows() {
    final rows = _sorted;
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (ctx, i) {
        final row = rows[i];
        final isHovered = _hoveredIndex == i;

        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredIndex = i),
          onExit: (_) => setState(() => _hoveredIndex = null),
          child: GestureDetector(
            onTap: widget.onRowTap != null ? () => widget.onRowTap!(row) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              color: isHovered
                  ? AppColors.deepNavy.withValues(alpha: 0.03)
                  : Colors.transparent,
              child: Row(
                children: [
                  ...widget.columns.map((col) {
                    final val = row[col.key];
                    return _DataCell(
                      column: col,
                      child: widget.cellBuilder != null
                          ? widget.cellBuilder!(col.key, val)
                          : Text(
                              val?.toString() ?? '—',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                              textAlign: col.align,
                              overflow: TextOverflow.ellipsis,
                            ),
                    );
                  }),
                  if (widget.rowActions != null)
                    SizedBox(
                      width: 120,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: widget.rowActions!(row),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: List.generate(
        8,
        (i) => Container(
          height: 52,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.shimmerBase.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text(
              'No records found',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final TableColumn column;
  final bool isSorted;
  final bool isAsc;
  final VoidCallback? onSort;

  const _HeaderCell({
    required this.column,
    required this.isSorted,
    required this.isAsc,
    this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Row(
      mainAxisAlignment: column.align == TextAlign.center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            column.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (column.sortable) ...[
          const SizedBox(width: 4),
          Icon(
            isSorted
                ? (isAsc ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.unfold_more,
            size: 14,
            color: isSorted ? AppColors.deepNavy : AppColors.textTertiary,
          ),
        ],
      ],
    );

    Widget cell = _cellWrapper(column, content);

    if (onSort != null) {
      return InkWell(
        onTap: onSort,
        child: cell,
      );
    }
    return cell;
  }
}

class _DataCell extends StatelessWidget {
  final TableColumn column;
  final Widget child;

  const _DataCell({required this.column, required this.child});

  @override
  Widget build(BuildContext context) {
    return _cellWrapper(
      column,
      Align(
        alignment: column.align == TextAlign.center
            ? Alignment.center
            : column.align == TextAlign.right
                ? Alignment.centerRight
                : Alignment.centerLeft,
        child: child,
      ),
    );
  }
}

Widget _cellWrapper(TableColumn col, Widget child) {
  if (col.width != null) {
    return SizedBox(
      width: col.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: child,
      ),
    );
  }
  return Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: child,
    ),
  );
}
