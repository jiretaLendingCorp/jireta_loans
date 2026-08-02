// lib/presentation/features/auth/widgets/password_strength_indicator.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

enum PasswordStrength { empty, weak, fair, strong, veryStrong }

class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({super.key, required this.password});

  static PasswordStrength evaluate(String password) {
    if (password.isEmpty) return PasswordStrength.empty;
    int score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) score++;

    if (score <= 1) return PasswordStrength.weak;
    if (score == 2) return PasswordStrength.fair;
    if (score == 3 || score == 4) return PasswordStrength.strong;
    return PasswordStrength.veryStrong;
  }

  @override
  Widget build(BuildContext context) {
    final strength = evaluate(password);
    if (strength == PasswordStrength.empty) return const SizedBox.shrink();

    final (label, color, filledBars) = switch (strength) {
      PasswordStrength.weak => ('Weak', AppColors.error, 1),
      PasswordStrength.fair => ('Fair', AppColors.warning, 2),
      PasswordStrength.strong => ('Strong', AppColors.success, 3),
      PasswordStrength.veryStrong => ('Very Strong', AppColors.riderGreen, 4),
      _ => ('', Colors.transparent, 0),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            return Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                height: 4,
                decoration: BoxDecoration(
                  color: i < filledBars ? color : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Use 8+ chars, uppercase, number & symbol',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ],
        ),
      ],
    );
  }
}
