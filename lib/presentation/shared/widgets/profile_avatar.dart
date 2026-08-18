// lib/presentation/shared/widgets/profile_avatar.dart
import 'package:flutter/material.dart';
import '../../../core/config/env_config.dart';

/// A read-only circular avatar that shows a user's profile photo when one is
/// set and falls back to their initial (or a supplied fallback widget)
/// otherwise. Unlike [ProfileAvatarUpload] this is not tappable and is safe to
/// use in staff-facing lists/details (head manager & employee views).
///
/// The image is clipped to the circle and scaled with `BoxFit.cover` so it
/// always fills the frame. `photoUrl` may be a full http(s) URL or a relative
/// storage path inside the public `avatars` bucket.
class ProfileAvatar extends StatefulWidget {
  final String? photoUrl;
  final String name;
  final Color color;
  final double radius;
  final Color textColor;
  final Widget? fallback;
  final Color? borderColor;
  final double borderWidth;

  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.color,
    this.radius = 18,
    this.textColor = Colors.white,
    this.fallback,
    this.borderColor,
    this.borderWidth = 2,
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

  String? get _resolvedUrl {
    final photo = widget.photoUrl;
    if (photo == null || photo.isEmpty) return null;
    if (photo.startsWith('http')) return photo;
    return '${EnvConfig.supabaseUrl}/storage/v1/object/public/avatars/$photo';
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolvedUrl;
    final diameter = widget.radius * 2;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: widget.borderColor != null
            ? Border.all(
                color: widget.borderColor!,
                width: widget.borderWidth,
              )
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: (url != null && !_imageFailed)
          ? Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _buildFallback(),
            )
          : _buildFallback(),
    );
  }

  Widget _buildFallback() {
    final fallback = widget.fallback;
    return ColoredBox(
      color: widget.color.withValues(alpha: 0.15),
      child: Center(
        child: fallback ??
            Text(
                widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: widget.radius * 0.9,
                  fontWeight: FontWeight.w700,
                )),
      ),
    );
  }
}