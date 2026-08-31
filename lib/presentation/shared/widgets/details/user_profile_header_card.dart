// lib/presentation/shared/widgets/details/user_profile_header_card.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../profile_avatar.dart';
import '../status_badge.dart';

class UserProfileHeaderCard extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final String? subtitle;
  final IconData? subtitleIcon;
  final String roleLabel;
  final Color accentColor;
  final IconData? roleIcon;
  final String accountStatus;
  final Widget? trailing;

  const UserProfileHeaderCard({
    super.key,
    this.photoUrl,
    required this.name,
    this.subtitle,
    this.subtitleIcon,
    required this.roleLabel,
    required this.accentColor,
    this.roleIcon,
    required this.accountStatus,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: accentColor.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            child: ProfileAvatar(
              photoUrl: photoUrl,
              name: name,
              color: accentColor,
              radius: 38,
              textColor: Colors.white,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    _roleChip(),
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        subtitleIcon ?? Icons.info_outline,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                StatusBadge(status: accountStatus),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 16),
            trailing!,
          ],
        ],
      ),
    );
  }

  Widget _roleChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (roleIcon != null) ...[
            Icon(roleIcon, size: 13, color: accentColor),
            const SizedBox(width: 4),
          ],
          Text(
            roleLabel.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accentColor,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}