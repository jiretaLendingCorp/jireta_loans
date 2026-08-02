// lib/presentation/shared/widgets/notification_badge.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class NotificationBadge extends StatelessWidget {
  final Widget child;
  final int count;
  final Color? color;

  const NotificationBadge({
    super.key,
    required this.child,
    required this.count,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: color ?? AppColors.error,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
