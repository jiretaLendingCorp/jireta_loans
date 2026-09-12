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
        // The Positioned MUST stay a direct child of this Stack. Wrapping it
        // inside the AnimatedSwitcher makes it land under the switcher's own
        // Stack (via FadeTransition/KeyedSubtree), which throws
        // "Incorrect use of ParentDataWidget"; the header then collapses into
        // a gray ErrorWidget box whenever there is an unread notification.
        Positioned(
          top: -4,
          right: -4,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
              ),
              child: FadeTransition(opacity: animation, child: child),
            ),
            // Pop whenever the count changes; fade/scale out when it hits 0.
            child: count > 0
                ? Container(
                    key: ValueKey<int>(count),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
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
                  )
                : const SizedBox.shrink(key: ValueKey<String>('empty')),
          ),
        ),
      ],
    );
  }
}
