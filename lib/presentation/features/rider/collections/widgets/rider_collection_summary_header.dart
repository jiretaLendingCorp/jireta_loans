// lib/presentation/features/rider/collections/widgets/rider_collection_summary_header.dart
import 'package:flutter/material.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../providers/rider_collection_summary_provider.dart';

/// Compact na summary ng sariling koleksyon ng rider: expected (due),
/// confirmed (verified lang), at remaining. Wala itong quota/target — monitoring
/// lang ng aktwal na naka-assign na installment at na-confirm na bayad.
class RiderCollectionSummaryHeader extends StatelessWidget {
  final RiderCollectionSummaryState state;
  final VoidCallback onRetry;
  final bool todayOnly;
  final ValueChanged<bool> onTodayChanged;

  const RiderCollectionSummaryHeader({
    super.key,
    required this.state,
    required this.onRetry,
    required this.todayOnly,
    required this.onTodayChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = state.summary;
    return Container(
      width: double.infinity,
      color: context.cSurface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined,
                  size: 16, color: context.cBrandGreen),
              const SizedBox(width: 6),
              Text(
                'My collections',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.cTextPrimary,
                ),
              ),
              const Spacer(),
              // Mabilis na filter ng mga account na due/visit ngayon.
              FilterChip(
                selected: todayOnly,
                onSelected: onTodayChanged,
                label: const Text('Today', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                selectedColor: AppColors.riderGreen.withValues(alpha: 0.15),
                checkmarkColor: AppColors.riderGreen,
                side: BorderSide(color: context.cBorder),
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      todayOnly ? AppColors.riderGreen : context.cTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (state.error != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.error),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Retry', style: TextStyle(fontSize: 11)),
                ),
              ],
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Amount(
                    label: 'Total Due',
                    value: s.expectedCollection,
                    color: context.cTextPrimary,
                  ),
                ),
                Expanded(
                  child: _Amount(
                    label: 'Confirmed',
                    value: s.confirmedCollection,
                    color: AppColors.success,
                  ),
                ),
                Expanded(
                  child: _Amount(
                    label: 'Remaining',
                    value: s.remainingDue,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
            if (s.overdueAccounts > 0 || s.overdueInstallments > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.statusOverdueBg.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 14, color: AppColors.statusOverdue),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${s.overdueAccounts} overdue account(s) · '
                        '${s.overdueInstallments} installment(s) need follow-up',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.statusOverdue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _Amount({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: context.cTextSecondary),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value.toPeso(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
