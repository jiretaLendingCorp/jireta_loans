// lib/presentation/shared/widgets/forms/anchored_dropdown.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Isang pagpipilian sa [AnchoredDropdownField]: [value] ang ipinapadala sa
/// `onChanged`, [label] ang nakikita ng user (hal. `self_employed` →
/// `Self-Employed`).
class AnchoredDropdownOption {
  final String value;
  final String label;
  const AnchoredDropdownOption(this.value, this.label);
}

/// Dropdown na NAKA-ANCHOR sa field nito.
///
/// BAKIT: ang `DropdownButtonFormField` ay naglalagay ng menu sa ibabaw ng
/// field — naka-align sa SELECTED item — kaya natatakpan nito ang sariling
/// field at ang mga kasunod na form field. Dito, ang menu ay:
///
///   * nasa IBABA ng field (4px gap) kapag may sapat na espasyo;
///   * awtomatikong nasa ITAAS ng field kapag kulang ang espasyo sa ibaba;
///   * kapareho ng lapad ng field, at hindi lalampas sa screen (nagiging
///     scrollable kapag mas mahaba sa available na espasyo ang mga option).
///
/// Sinusuportahan din nito ang `Form` validation (`validator`) at ang panlabas
/// na error text ([errorText]).
class AnchoredDropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<AnchoredDropdownOption> options;
  final ValueChanged<String?>? onChanged;
  final String? Function(String?)? validator;

  /// Panlabas na error text (hal. galing sa screen state) — kaparehong lugar
  /// ito ng error text ng `DropdownButtonFormField`.
  final String? errorText;

  /// Kapag false (o walang `onChanged`/options), hindi mabubuksan ang menu.
  final bool enabled;

  const AnchoredDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    this.onChanged,
    this.validator,
    this.errorText,
    this.enabled = true,
  });

  /// Gap ng menu sa field.
  static const double _gap = 4;

  /// Taas ng isang menu item + ang 8px padding sa itaas at ibaba ng menu.
  static const double _menuItemHeight = 44;
  static const double _menuVerticalPadding = 16;

  /// Pinakamaliit na taas ng bakanteng 8px sa gilid ng screen.
  static const double _screenEdgePadding = 8;

  bool get _isEnabled => enabled && onChanged != null && options.isNotEmpty;

  String? _labelFor(String? current) {
    for (final option in options) {
      if (option.value == current) return option.label;
    }
    return current;
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: value,
      validator: validator,
      builder: (field) {
        final current = value;
        final hasValue = current != null && current.isNotEmpty;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _isEnabled ? () => _openMenu(context, field) : null,
          child: InputDecorator(
            isEmpty: !hasValue,
            decoration: _decoration(field.errorText),
            child: Text(
              _labelFor(current) ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color:
                    hasValue ? AppColors.textPrimary : AppColors.textTertiary,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Binubuksan ang menu: IBABA ng field kung kasya, ITAAS kung hindi.
  Future<void> _openMenu(
      BuildContext context, FormFieldState<String> field) async {
    final overlay =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.hasSize || !overlay.hasSize) {
      return;
    }

    // Posisyon ng field sa screen (sa coordinates ng overlay).
    final fieldRect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final screen = Offset.zero & overlay.size;

    // Tantya ng buong taas ng menu (hindi pa kasama ang pag-cap sa screen).
    final contentHeight =
        options.length * _menuItemHeight + _menuVerticalPadding;
    final spaceBelow = screen.bottom - fieldRect.bottom - _gap;
    final spaceAbove = fieldRect.top - screen.top - _gap;

    // Kulang ang ibaba at mas maluwag sa itaas → sa ITAAS ng field.
    final openAbove = spaceBelow < contentHeight && spaceAbove > spaceBelow;
    final available = openAbove ? spaceAbove : spaceBelow;
    final menuHeight = math.min(
      contentHeight,
      math.max(available, _menuItemHeight),
    );
    final menuTop =
        openAbove ? fieldRect.top - _gap - menuHeight : fieldRect.bottom + _gap;
    final clampedTop = math.max(
      screen.top + _screenEdgePadding,
      math.min(menuTop, screen.bottom - _screenEdgePadding - menuHeight),
    );

    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        fieldRect.left,
        clampedTop,
        screen.right - fieldRect.right,
        screen.bottom - (clampedTop + menuHeight),
      ),
      initialValue: value,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      // Parehong lapad ng field ang menu.
      constraints: BoxConstraints.tightFor(width: fieldRect.width),
      items: [
        for (final option in options)
          PopupMenuItem<String>(
            value: option.value,
            height: _menuItemHeight,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: option.value == value
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (option.value == value)
                  const Icon(Icons.check_rounded,
                      size: 18, color: AppColors.lenderBlue),
              ],
            ),
          ),
      ],
    );

    if (picked == null) return;
    field.didChange(picked);
    onChanged?.call(picked);
  }

  InputDecoration _decoration(String? fieldError) {
    final error = fieldError ?? errorText;
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      counterText: '',
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      errorText: error,
      errorStyle: const TextStyle(fontSize: 11.5, color: AppColors.error),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: error != null ? AppColors.error : AppColors.border,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.lenderBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded,
          size: 20, color: AppColors.textSecondary),
    );
  }
}
