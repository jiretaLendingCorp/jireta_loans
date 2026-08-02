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
    final result = await showDateRangePicker(
      context: context,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
      initialDateRange: value,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.deepNavy,
            onPrimary: Colors.white,
            secondary: AppColors.gold,
          ),
        ),
        child: child!,
      ),
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
