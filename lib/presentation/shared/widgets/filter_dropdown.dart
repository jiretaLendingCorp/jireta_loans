// lib/presentation/shared/widgets/filter_dropdown.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Dropdown na filter na PAREHO ang ayos ng katabi nito sa toolbar
/// (`SearchDateFilter` at `SearchResultsChip`): puti, 48px ang taas, 8px
/// radius, manipis na border, may sariling arrow — walang underline.
///
/// Dati kasing hubad na `DropdownButton` ang mga filter na ito: may underline,
/// ibang taas at ibang kulay ng text, kaya hindi pantay-pantay ang dating ng
/// apat na controls sa isang toolbar (hal. `/hm/all-users`: `Filter Date` at
/// `20 results` ay bordered pill, ang `All Roles` / `All Status` ay hilaw na
/// dropdown na may guhit sa ilalim).
class FilterDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  /// Teksto kapag wala pang napiling value (`value == null`).
  final String? hint;

  /// Opsyonal na icon sa unahan ng label — kapareho ng icons ng ibang pills.
  final IconData? icon;

  const FilterDropdown({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.hint,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
          ],
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isDense: true,
              hint: hint == null
                  ? null
                  : Text(
                      hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
              // Kapareho ng label ng results chip — maliit at bold.
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              icon: const Icon(Icons.arrow_drop_down,
                  size: 18, color: AppColors.textTertiary),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }
}
