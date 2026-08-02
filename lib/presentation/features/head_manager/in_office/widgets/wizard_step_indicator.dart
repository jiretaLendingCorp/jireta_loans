// lib/presentation/features/head_manager/in_office/widgets/wizard_step_indicator.dart
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

class WizardStepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final List<String> stepLabels;

  const WizardStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.stepLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: List.generate(totalSteps * 2 - 1, (index) {
          if (index.isOdd) {
            final stepIndex = index ~/ 2;
            final isCompleted = stepIndex < currentStep;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 2,
                color: isCompleted ? AppColors.gold : AppColors.border,
              ),
            );
          }

          final stepIndex = index ~/ 2;
          final isCompleted = stepIndex < currentStep;
          final isCurrent = stepIndex == currentStep;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? AppColors.gold
                      : isCurrent
                          ? AppColors.primary
                          : AppColors.border,
                  border: Border.all(
                    color: isCurrent ? AppColors.gold : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '${stepIndex + 1}',
                          style: TextStyle(
                            color: isCurrent
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
              if (stepLabels.length > stepIndex) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: 70,
                  child: Text(
                    stepLabels[stepIndex],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isCurrent || isCompleted
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}
