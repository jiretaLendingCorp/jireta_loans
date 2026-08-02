// lib/presentation/shared/widgets/tables/table_filter_bar.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class TableFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final String searchHint;
  final List<FilterChipData> chips;
  final VoidCallback? onExportCsv;
  final ValueChanged<String>? onSearch;
  final Widget? extra;

  const TableFilterBar({
    super.key,
    required this.searchController,
    this.searchHint = 'Search...',
    this.chips = const [],
    this.onExportCsv,
    this.onSearch,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            height: 38,
            child: TextField(
              controller: searchController,
              onChanged: onSearch,
              decoration: InputDecoration(
                hintText: searchHint,
                hintStyle: const TextStyle(
                    fontSize: 13, color: AppColors.textTertiary),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: AppColors.textTertiary),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.deepNavy, width: 1.5),
                ),
                filled: true,
                fillColor: AppColors.surfaceWhite,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          ...chips.map((c) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterDropdown(data: c),
              )),
          if (extra != null) ...[const SizedBox(width: 8), extra!],
          const Spacer(),
          if (onExportCsv != null)
            OutlinedButton.icon(
              onPressed: onExportCsv,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Export', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepNavy,
                side: const BorderSide(color: AppColors.border),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FilterChipData {
  final String label;
  final String value;
  final List<String> options;
  final void Function(String) onChanged;

  const FilterChipData({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
}

class _FilterDropdown extends StatelessWidget {
  final FilterChipData data;
  const _FilterDropdown({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: data.value != 'all'
            ? AppColors.deepNavy.withValues(alpha: 0.06)
            : AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: data.value != 'all'
              ? AppColors.deepNavy.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: data.value,
          hint: Text(data.label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          isDense: true,
          icon: const Icon(Icons.expand_more, size: 16),
          style: const TextStyle(
              fontSize: 13, color: AppColors.textPrimary, fontFamily: 'Inter'),
          onChanged: (v) => data.onChanged(v ?? 'all'),
          items: data.options
              .map((o) => DropdownMenuItem(
                    value: o,
                    child: Text(
                      o == 'all'
                          ? '${data.label}: All'
                          : o.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

TableFilterBar buildFilterBar({
  required TextEditingController searchController,
  String searchHint = 'Search...',
  List<
          ({
            String label,
            String value,
            List<String> options,
            void Function(String) onChanged
          })>
      filters = const [],
  VoidCallback? onExport,
  ValueChanged<String>? onSearch,
  Widget? extra,
}) {
  return TableFilterBar(
    searchController: searchController,
    searchHint: searchHint,
    onSearch: onSearch,
    chips: filters
        .map((f) => FilterChipData(
              label: f.label,
              value: f.value,
              options: f.options,
              onChanged: f.onChanged,
            ))
        .toList(),
    onExportCsv: onExport,
    extra: extra,
  );
}
