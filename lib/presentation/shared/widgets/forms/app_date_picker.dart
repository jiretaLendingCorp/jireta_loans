// lib/presentation/shared/widgets/forms/app_date_picker.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';

class AppDatePicker extends StatelessWidget {
  final String label;
  final DateTime? selectedDate;
  final DateTime? value;
  final Function(DateTime)? onDateSelected;
  final Function(DateTime)? onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;

  /// Kapag true, may kasunod na TIME picker pagkatapos pumili ng petsa — ang
  /// ibabalik na DateTime ay may oras na (para sa "anong oras pupunta si rider").
  final bool withTime;

  const AppDatePicker({
    super.key,
    required this.label,
    this.selectedDate,
    this.value,
    this.onDateSelected,
    this.onChanged,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
    this.withTime = false,
  });

  DateTime? get _date => value ?? selectedDate;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: firstDate ?? DateTime(1900),
      lastDate: lastDate ?? DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.deepNavy,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
          datePickerTheme: const DatePickerThemeData(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    var result = picked;
    if (withTime) {
      if (!context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_date ?? DateTime.now()),
      );
      // Kinansela ang oras → huwag i-report ang petsa. Kailangan may oras
      // (required ito sa mga assign-rider flow), kaya hayaan ang validation na
      // humingi muli ng buong petsa at oras.
      if (time == null) return;
      result = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time.hour,
        time.minute,
      );
    }
    (onChanged ?? onDateSelected)?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat(
      withTime ? 'MMM d, y h:mm a' : 'MMM d, y',
      'en_PH',
    );
    return GestureDetector(
      onTap: enabled ? () => _pick(context) : null,
      child: AbsorbPointer(
        child: TextFormField(
          readOnly: true,
          enabled: enabled,
          controller: TextEditingController(
            text: _date != null ? fmt.format(_date!) : '',
          ),
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: Icon(
              withTime ? Icons.event_available_outlined : Icons.calendar_today_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: AppColors.border),
            ),
            filled: true,
            fillColor: enabled ? Colors.white : AppColors.surfaceVariant,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            labelStyle: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
