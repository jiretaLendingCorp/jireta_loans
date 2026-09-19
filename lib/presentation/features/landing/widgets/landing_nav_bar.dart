// lib/presentation/features/landing/widgets/landing_nav_bar.dart
//
// The landing page reuses the app's own public header (WebAuthHeader), so the
// top of the marketing site is the exact same component as the sign-in and
// registration screens. All that lives here is the panel the header opens on
// narrow screens, where the section links no longer fit in the bar.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'landing_shared.dart';

/// Section list shown under the header below the tablet breakpoint.
class LandingMobileMenu extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onSignIn;
  final VoidCallback onGetStarted;

  const LandingMobileMenu({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.onSelect,
    required this.onSignIn,
    required this.onGetStarted,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        LandingBreakpoints.gutter(width),
        4,
        LandingBreakpoints.gutter(width),
        20,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE9E9EE)),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < labels.length; i++)
            _MobileMenuLink(
              label: labels[i],
              active: activeIndex == i,
              onTap: () => onSelect(i),
            ),
          const SizedBox(height: 14),
          LandingPrimaryButton(
            label: 'Get Started',
            trailingIcon: Icons.arrow_forward_rounded,
            onTap: onGetStarted,
          ),
          const SizedBox(height: 10),
          LandingGhostButton(label: 'Sign In', onTap: onSignIn),
        ],
      ),
    );
  }
}

class _MobileMenuLink extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _MobileMenuLink({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: active ? AppColors.gold : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? AppColors.deepNavy : AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Color(0xFF9AA2B1),
            ),
          ],
        ),
      ),
    );
  }
}
