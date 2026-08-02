// lib/presentation/shared/widgets/forms/app_text_field.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';

class AppTextField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool readOnly;
  final int? maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? prefixIcon;
  final Widget? suffix;
  final VoidCallback? onTap;
  final Function(String)? onChanged;
  final bool showPasswordToggle;
  final bool enabled;
  final FocusNode? focusNode;
  final String? initialValue;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.prefixIcon,
    this.suffix,
    this.onTap,
    this.onChanged,
    this.showPasswordToggle = false,
    this.enabled = true,
    this.focusNode,
    this.initialValue,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      initialValue: widget.initialValue,
      validator: widget.validator,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText && _obscure,
      readOnly: widget.readOnly,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      enabled: widget.enabled,
      focusNode: widget.focusNode,
      onTap: widget.onTap,
      onChanged: widget.onChanged,
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.textPrimary,
        fontFamily: 'Inter',
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        hintStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textTertiary,
        ),
        prefixIcon: widget.prefixIcon != null
            ? Icon(widget.prefixIcon, size: 18, color: AppColors.textSecondary)
            : null,
        suffixIcon: widget.showPasswordToggle
            ? GestureDetector(
                onTap: () => setState(() => _obscure = !_obscure),
                child: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              )
            : widget.suffix,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        filled: true,
        fillColor: widget.enabled ? Colors.white : AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        floatingLabelStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.deepNavy,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
