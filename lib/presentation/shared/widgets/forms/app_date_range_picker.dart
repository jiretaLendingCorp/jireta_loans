// lib/presentation/shared/widgets/forms/app_date_range_picker.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';

class AppDateRangePicker extends StatelessWidget {
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const AppDateRangePicker({
    super.key,
    this.value,
    required this.onChanged,
    this.label = 'Date Range',
    this.firstDate,
    this.lastDate,
  });

  String get _displayText {
    if (value == null) return 'Select date range';
    final f = DateFormat('MMM d, yyyy');
    return '${f.format(value!.start)} – ${f.format(value!.end)}';
  }

  Future<void> _pick(BuildContext context) async {
    final result = await showAppDateRangePicker(
      context: context,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
      initialDateRange: value,
    );
    onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
        ],
        GestureDetector(
          onTap: () => _pick(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                  color: value != null ? AppColors.deepNavy : AppColors.border),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
            ),
            child: Row(children: [
              Icon(Icons.date_range,
                  size: 18,
                  color:
                      value != null ? AppColors.deepNavy : AppColors.textHint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _displayText,
                  style: TextStyle(
                    fontSize: 14,
                    color: value != null
                        ? AppColors.textPrimary
                        : AppColors.textHint,
                  ),
                ),
              ),
              if (value != null)
                GestureDetector(
                  onTap: () => onChanged(null),
                  child: const Icon(Icons.close,
                      size: 16, color: AppColors.textHint),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Opens the app's custom modal date-range picker (grey header, flat/square
/// style consistent with the rest of the app) and returns the picked range,
/// or null if the user cancels.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  DateTime? firstDate,
  DateTime? lastDate,
  DateTimeRange? initialDateRange,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (_) => AppDateRangePickerDialog(
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initialDateRange,
    ),
  );
}

/// Custom modal date-range selector used across the app in place of the
/// default Material date-range dialog.
class AppDateRangePickerDialog extends StatefulWidget {
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialDateRange;

  const AppDateRangePickerDialog({
    super.key,
    required this.firstDate,
    required this.lastDate,
    this.initialDateRange,
  });

  @override
  State<AppDateRangePickerDialog> createState() =>
      _AppDateRangePickerDialogState();
}

class _AppDateRangePickerDialogState extends State<AppDateRangePickerDialog> {
  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  late DateTime _month;
  DateTime? _start;
  DateTime? _end;
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final init = widget.initialDateRange;
    _start = init?.start;
    _end = init?.end;
    if (init != null) {
      _fromCtrl.text = _fmt(init.start);
      _toCtrl.text = _fmt(init.end);
    }
    final ref = init?.start ?? DateTime.now();
    _month = DateTime(ref.year, ref.month);
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  static String _fmt(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  static DateTime? _parseDate(String input) {
    final t = input.trim();
    for (final fmt in ['MM/dd/yyyy', 'M/d/yyyy', 'yyyy-MM-dd']) {
      final d = DateFormat(fmt).tryParse(t);
      if (d != null) return d;
    }
    return null;
  }

  void _onFromChanged(String v) {
    final t = v.trim();
    if (t.isEmpty) {
      setState(() => _start = null);
      return;
    }
    final d = _parseDate(t);
    if (d == null ||
        d.isBefore(widget.firstDate) ||
        d.isAfter(widget.lastDate)) {
      return;
    }
    setState(() => _start = d);
  }

  void _onToChanged(String v) {
    final t = v.trim();
    if (t.isEmpty) {
      setState(() => _end = null);
      return;
    }
    final d = _parseDate(t);
    if (d == null ||
        d.isBefore(widget.firstDate) ||
        d.isAfter(widget.lastDate)) {
      return;
    }
    setState(() => _end = d);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _onDayTap(DateTime day) {
    if (day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate)) {
      return;
    }
    setState(() {
      if (_start == null || _end != null) {
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        _start = day;
      } else {
        _end = day;
      }
    });
    _fromCtrl.text = _fmt(_start!);
    _toCtrl.text = _end == null ? '' : _fmt(_end!);
  }

  bool _inRange(DateTime day) =>
      _start != null &&
      _end != null &&
      !day.isBefore(_start!) &&
      !day.isAfter(_end!);

  bool _isDisabled(DateTime day) =>
      day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate);

  Widget _dayCell(DateTime day) {
    final isStart = _start != null && _sameDay(day, _start!);
    final isEnd = _end != null && _sameDay(day, _end!);
    final isRangeDay = _inRange(day) && !isStart && !isEnd;
    final disabled = _isDisabled(day);
    final isToday = _sameDay(day, DateTime.now());

    return InkWell(
      onTap: disabled ? null : () => _onDayTap(day),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isStart || isEnd
              ? AppColors.deepNavy
              : isRangeDay
                  ? AppColors.deepNavy.withValues(alpha: 0.10)
                  : null,
        ),
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                isStart || isEnd ? FontWeight.w800 : FontWeight.w500,
            color: disabled
                ? AppColors.textTertiary.withValues(alpha: 0.35)
                : isStart || isEnd
                    ? Colors.white
                    : isToday
                        ? AppColors.deepNavy
                        : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  void _prevMonth() {
    final m = DateTime(_month.year, _month.month - 1);
    if (m.isBefore(
        DateTime(widget.firstDate.year, widget.firstDate.month))) {
      return;
    }
    setState(() => _month = m);
  }

  void _nextMonth() {
    final m = DateTime(_month.year, _month.month + 1);
    if (m.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month))) {
      return;
    }
    setState(() => _month = m);
  }

  List<Widget> _buildGrid() {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday-first layout
    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(_dayCell(DateTime(_month.year, _month.month, d)));
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('MMMM yyyy');
    final grid = _buildGrid();
    // Apply ay nakabase sa mismong na-type sa fields, hindi sa stale state.
    final from = _parseDate(_fromCtrl.text);
    final to = _parseDate(_toCtrl.text);
    final canApply = from != null &&
        to != null &&
        !from.isBefore(widget.firstDate) &&
        !from.isAfter(widget.lastDate) &&
        !to.isBefore(widget.firstDate) &&
        !to.isAfter(widget.lastDate);
    return Dialog(
      shape: const RoundedRectangleBorder(),
      backgroundColor: Colors.white,
      child: SizedBox(
        width: 330,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grey header
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              color: const Color(0xFF5C6370),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Select Date Range',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Editable From / To fields — nag-sync sa calendar below.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'From',
                      controller: _fromCtrl,
                      onChanged: _onFromChanged,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: 'To',
                      controller: _toCtrl,
                      onChanged: _onToChanged,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _prevMonth,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      f.format(_month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  IconButton(
                    onPressed: _nextMonth,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      for (final w in _weekdayLabels)
                        Expanded(
                          child: SizedBox(
                            height: 28,
                            child: Center(
                              child: Text(w,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textTertiary)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (var r = 0; r < grid.length; r += 7)
                    Row(
                      children: [
                        for (var c = 0; c < 7; c++)
                          Expanded(
                            child: SizedBox(
                              height: 34,
                              child: grid[r + c],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),

                  ElevatedButton(
                    onPressed: canApply
                        ? () {
                            var start = from;
                            var end = to;
                            if (start.isAfter(end)) {
                              final t = start;
                              start = end;
                              end = t;
                            }
                            Navigator.pop(
                                context, DateTimeRange(start: start, end: end));
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5C6370),
                      disabledBackgroundColor:
                          const Color(0xFF5C6370).withValues(alpha: 0.35),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: const RoundedRectangleBorder(),
                    ),
                    child: const Text('Apply',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editable date input used inside the date-range modal (From / To).
class _DateField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _DateField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'MM/DD/YYYY',
            hintStyle:
                TextStyle(fontSize: 12, color: AppColors.textTertiary),
            isDense: true,
            filled: true,
            fillColor: Color(0xFFF3F4F6),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide:
                  BorderSide(color: AppColors.borderDark, width: 1),
            ),
          ),
        ),
      ],
    );
  }
}
