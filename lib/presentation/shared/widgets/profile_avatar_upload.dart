// lib/presentation/shared/widgets/profile_avatar_upload.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/config/env_config.dart';
import '../../../core/services/supabase_storage_service.dart';
import '../../../core/theme/app_colors.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

/// A profile avatar that lets every user change their own profile picture.
/// Uploads to the `avatars` public bucket and returns the public URL.
class ProfileAvatarUpload extends StatefulWidget {
  final String? photoUrl;
  final String name;
  final Color color;
  final double radius;
  final Future<void> Function(String url) onUploaded;

  const ProfileAvatarUpload({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.color,
    required this.onUploaded,
    this.radius = 44,
  });

  @override
  State<ProfileAvatarUpload> createState() => _ProfileAvatarUploadState();
}

class _ProfileAvatarUploadState extends State<ProfileAvatarUpload> {
  bool _uploading = false;
  bool _imageFailed = false;

  @override
  void didUpdateWidget(covariant ProfileAvatarUpload oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      _imageFailed = false;
    }
  }

  String get _publicUrl =>
      '${EnvConfig.supabaseUrl}/storage/v1/object/public/avatars/';

  Future<void> _pickAndUpload() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final path = await SupabaseStorageService.instance.uploadFile(
        bucket: 'avatars',
        bytes: bytes,
        fileName: picked.name,
        folder: 'profiles',
        contentType: 'image/jpeg',
      );
      final publicUrl = '$_publicUrl$path';
      await widget.onUploaded(publicUrl);
      if (mounted) {
        context.showSnackBarAsToast(
          const SnackBar(
            content: Text('Profile picture updated'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBarAsToast(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _buildFallback() => Text(
        widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: widget.radius * 0.8,
          fontWeight: FontWeight.w700,
          color: widget.color,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final photo = widget.photoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty && !_imageFailed;
    return GestureDetector(
      onTap: _uploading ? null : _pickAndUpload,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: widget.radius,
            backgroundColor: widget.color.withValues(alpha: 0.15),
            backgroundImage: hasPhoto ? NetworkImage(photo) : null,
            onBackgroundImageError: hasPhoto
                ? (_, __) {
                    setState(() => _imageFailed = true);
                  }
                : null,
            child: !hasPhoto ? _buildFallback() : null,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: _uploading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.camera_alt, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
