// lib/presentation/shared/widgets/forms/app_dropdown.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class AppDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final Function(T?)? onChanged;
  final String? Function(T?)? validator;
  final bool enabled;
  final IconData? prefixIcon;

  const AppDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: enabled ? onChanged : null,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 18, color: AppColors.textSecondary)
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.deepNavy, width: 1.5),
        ),
        filled: true,
        fillColor: enabled ? Colors.white : AppColors.surfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle:
            const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      dropdownColor: Colors.white,
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.textPrimary,
        fontFamily: 'Inter',
      ),
      borderRadius: BorderRadius.circular(10),
      icon:
          const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
    );
  }
}
