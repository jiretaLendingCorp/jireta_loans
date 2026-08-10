// lib/presentation/shared/widgets/profile_avatar.dart
import 'package:flutter/material.dart';

/// A read-only circular avatar that shows a user's profile photo when one is
/// set and falls back to their initial (or a supplied fallback widget)
/// otherwise. Unlike [ProfileAvatarUpload] this is not tappable and is safe to
/// use in staff-facing lists/details (head manager & employee views).
class ProfileAvatar extends StatefulWidget {
  final String? photoUrl;
  final String name;
  final Color color;
  final double radius;
  final Color textColor;
  final Widget? fallback;

  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.color,
    this.radius = 18,
    this.textColor = Colors.white,
    this.fallback,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  bool _imageFailed = false;

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      _imageFailed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty && !_imageFailed;
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.color.withValues(alpha: 0.15),
      backgroundImage: hasPhoto ? NetworkImage(photo) : null,
      onBackgroundImageError: hasPhoto
          ? (_, __) {
              setState(() => _imageFailed = true);
            }
          : null,
      child: !hasPhoto ? (widget.fallback ?? _buildInitial()) : null,
    );
  }

  Widget _buildInitial() => Text(
        widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
        style: TextStyle(
          color: widget.textColor,
          fontSize: widget.radius * 0.9,
          fontWeight: FontWeight.w700,
        ),
      );
}