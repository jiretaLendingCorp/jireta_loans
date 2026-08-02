// lib/presentation/shared/widgets/upload_progress_widget.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class UploadProgressWidget extends StatelessWidget {
  final String fileName;
  final double progress;
  final bool isComplete;
  final bool hasError;
  final VoidCallback? onRemove;

  const UploadProgressWidget({
    super.key,
    required this.fileName,
    required this.progress,
    this.isComplete = false,
    this.hasError = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = hasError
        ? AppColors.error
        : isComplete
            ? AppColors.success
            : AppColors.deepNavy;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasError
                    ? Icons.error_outline
                    : isComplete
                        ? Icons.check_circle_outline
                        : Icons.insert_drive_file_outlined,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isComplete || hasError)
                Text(
                  isComplete ? '100%' : 'Error',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                )
              else
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              if (onRemove != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
          if (!isComplete && !hasError) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
