// lib/presentation/shared/widgets/search_date_filter.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import 'forms/app_date_range_picker.dart';

/// Compact date filter button that sits beside the search field and results
/// chip. Height (48px) matches the search TextField.
///
/// The user can pick a filter mode:
///  - "By Month"    → pick a month/year; resolves to the full Manila month.
///  - "By Date Range" → pick a from/to range (standard date-range picker).
///
/// Always reports the effective selection as a [DateTimeRange] through
/// [onChanged]; a clear (×) button resets the filter.
class SearchDateFilter extends StatefulWidget {
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  const SearchDateFilter({super.key, required this.value, required this.onChanged});

  /// Convert a picked (local) day to the UTC instant of Manila (UTC+8)
  /// midnight for that day, so the backend `created_at >= ?` filter covers
  /// the whole Manila calendar day (not just UTC midnight).
  static String fromParam(DateTime day) {
    final utcMidnight = DateTime.utc(day.year, day.month, day.day);
    return utcMidnight.subtract(const Duration(hours: 8)).toIso8601String();
  }

  /// End-of-day (Manila 23:59:59.999) as a UTC instant for `created_at <= ?`.
  static String toParam(DateTime day) {
    final utcMidnight = DateTime.utc(day.year, day.month, day.day);
    return utcMidnight
        .add(const Duration(hours: 16)) // 24h - 8h offset
        .subtract(const Duration(milliseconds: 1))
        .toIso8601String();
  }

  @override
  State<SearchDateFilter> createState() => _SearchDateFilterState();
}

enum _DateFilterMode { month, range }

class _SearchDateFilterState extends State<SearchDateFilter> {
  _DateFilterMode _mode = _DateFilterMode.range;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Future<void> _pickRange() async {
    final result = await showAppDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: widget.value,
    );
    widget.onChanged(result);
  }

  Future<void> _pickMonth() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthPickerDialog(initial: _month),
    );
    if (picked == null) return;
    setState(() => _month = DateTime(picked.year, picked.month));
    widget.onChanged(DateTimeRange(
      start: DateTime(_month.year, _month.month, 1),
      end: DateTime(_month.year, _month.month + 1, 0), // last day of month
    ));
  }

  void _selectMode(_DateFilterMode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    // Switching mode resets an existing filter so the new mode starts clean.
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('MMM d, yyyy');
    final mf = DateFormat('MMM yyyy');
    final active = widget.value != null;
    final label = !active
        ? 'Filter Date'
        : _mode == _DateFilterMode.month
            ? mf.format(_month)
            : '${f.format(widget.value!.start)} – ${f.format(widget.value!.end)}';

    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 8, right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? AppColors.deepNavy : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<_DateFilterMode>(
            tooltip: 'Filter mode',
            initialValue: _mode,
            onSelected: _selectMode,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _DateFilterMode.month,
                child: Text('By Month', style: TextStyle(fontSize: 13)),
              ),
              PopupMenuItem(
                value: _DateFilterMode.range,
                child: Text('By Date Range', style: TextStyle(fontSize: 13)),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _mode == _DateFilterMode.month
                        ? Icons.calendar_month_outlined
                        : Icons.date_range_outlined,
                    size: 15,
                    color: active ? AppColors.deepNavy : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down,
                      size: 16, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: _mode == _DateFilterMode.month ? _pickMonth : _pickRange,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? AppColors.deepNavy : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () => widget.onChanged(null),
              borderRadius: BorderRadius.circular(6),
              child: const Icon(Icons.close,
                  size: 15, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact month/year picker dialog (grid of 12 months + year navigation).
class _MonthPickerDialog extends StatefulWidget {
  final DateTime initial;
  const _MonthPickerDialog({required this.initial});

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  late int _year = widget.initial.year;
  late final int _selectedMonth = widget.initial.month;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
      title: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: () => setState(() => _year--),
          ),
          Expanded(
            child: Center(
              child: Text(
                '$_year',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: _year >= now.year
                ? null
                : () => setState(() => _year++),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      content: SizedBox(
        width: 300,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.3,
          children: List.generate(12, (i) {
            final month = i + 1;
            final isCurrent = _year == widget.initial.year && month == _selectedMonth;
            return InkWell(
              onTap: () => Navigator.of(context).pop(DateTime(_year, month)),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppColors.deepNavy
                      : const Color(0xFFF4F5F7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent ? AppColors.deepNavy : Colors.transparent,
                  ),
                ),
                child: Text(
                  _months[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isCurrent ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}