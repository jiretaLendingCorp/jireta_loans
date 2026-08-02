// lib/presentation/shared/widgets/tables/table_pagination.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class TablePagination extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final void Function(int) onPageChange;

  const TablePagination({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.onPageChange,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            'Total: $totalCount records',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const Spacer(),
          _PageBtn(
            icon: Icons.chevron_left,
            enabled: currentPage > 1,
            onTap: () => onPageChange(currentPage - 1),
          ),
          const SizedBox(width: 4),
          ...List.generate(totalPages, (i) {
            final page = i + 1;
            final isSelected = page == currentPage;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: GestureDetector(
                onTap: () => onPageChange(page),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.deepNavy : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? AppColors.deepNavy : AppColors.border,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$page',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 4),
          _PageBtn(
            icon: Icons.chevron_right,
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
  final bool enabled;
  final VoidCallback onTap;

  const _PageBtn(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
        ),
      ),
    );
  }
}
