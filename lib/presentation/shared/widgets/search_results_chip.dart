// lib/presentation/shared/widgets/search_results_chip.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Compact "N results" chip shown beside search fields so users can see
/// how many rows match the current filter/search. Height matches the search
/// TextField (48px) and the style stays neutral (white, no blue).
class SearchResultsChip extends StatelessWidget {
  final int count;
  const SearchResultsChip({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    // IntrinsicWidth keeps the pill compact (content-sized) inside a Wrap
    // on mobile. A plain Container with alignment would expand to the full
    // run width, stretching the chip full-width below the Filter Date.
    return IntrinsicWidth(
      child: Container(
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
            const Icon(Icons.layers_outlined, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              '$count result${count == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}