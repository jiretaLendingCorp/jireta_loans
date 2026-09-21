// lib/presentation/shared/widgets/tables/records_pagination.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Page controls na KAPAREHO ng nasa Loan Records: `<` button, navy na
/// `1 / 2` pill, `>` button — right-aligned at nasa ILALIM ng table, hindi
/// hiwalay na footer bar.
///
/// Bakit ganito at hindi ang dating buong-lapad na footer: ang
/// `TablePagination` ay may puting strip at top border na lumalabas na parang
/// hiwalay na bahagi ng page ("Total: N records" sa kaliwa) — ang bersyon na
/// ito ay bahagi lang ng content area, gaya ng nasa Loan Records list.
///
/// Hindi ito nagre-render kapag isang page lang (`totalPages <= 1`).
class RecordsPagination extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final void Function(int) onPageChange;

  const RecordsPagination({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChange,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          const Spacer(),
          _PageBtn(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous page',
            enabled: currentPage > 1,
            onTap: () => onPageChange(currentPage - 1),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$currentPage / $totalPages',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          _PageBtn(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next page',
            enabled: currentPage < totalPages,
            onTap: () => onPageChange(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

class _PageBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _PageBtn({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: enabled ? Colors.white : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: enabled ? AppColors.border : AppColors.divider),
          ),
          child: Icon(icon,
              size: 18,
              color: enabled ? AppColors.textPrimary : AppColors.textTertiary),
        ),
      ),
    );
  }
}
