// lib/presentation/features/rider/ci/screens/rider_upload_ci_documents_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/image/xfile_preview.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../providers/rider_ci_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class _CiPhoto {
  final XFile file;
  final String caption;
  final String type;

  _CiPhoto({required this.file, required this.caption, required this.type});
  _CiPhoto copyWith({String? caption, String? type}) => _CiPhoto(
      file: file, caption: caption ?? this.caption, type: type ?? this.type);
}

class RiderUploadCiDocumentsScreen extends ConsumerStatefulWidget {
  final String ciId;
  const RiderUploadCiDocumentsScreen({super.key, required this.ciId});

  @override
  ConsumerState<RiderUploadCiDocumentsScreen> createState() =>
      _RiderUploadCiDocumentsScreenState();
}

class _RiderUploadCiDocumentsScreenState
    extends ConsumerState<RiderUploadCiDocumentsScreen> {
  final _picker = ImagePicker();
  final List<_CiPhoto> _photos = [];
  bool _isUploading = false;

  static const _photoTypes = [
    'site_photo',
    'neighbor_interview',
    'proof_of_residence',
    'other',
  ];
  static const _typeLabels = {
    'site_photo': 'Site Photo',
    'neighbor_interview': 'Neighbor Interview',
    'proof_of_residence': 'Proof of Residence',
    'other': 'Other',
  };

  Future<void> _addPhoto() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add Photo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt, color: AppColors.riderGreen),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.info),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;
    final picked = await _picker.pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked != null) {
      setState(() =>
          _photos.add(_CiPhoto(file: picked, caption: '', type: 'site_photo')));
    }
  }

  Future<void> _uploadAll() async {
    if (_photos.isEmpty) {
      context.showSnackBarAsToast(
        const SnackBar(
            content: Text('Please add at least one photo'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      int successCount = 0;
      for (final photo in _photos) {
        final ok = await ref.read(riderCiProvider.notifier).uploadDocument(
              ciId: widget.ciId,
              file: photo.file,
              documentType: photo.type,
              caption: photo.caption.isEmpty ? null : photo.caption,
            );
        if (ok) successCount++;
      }

      if (mounted) {
        if (successCount > 0) {
          await showDialog(
            context: context,
            builder: (_) => SuccessDialog(
                message:
                    '$successCount photo(s) uploaded successfully with GPS coordinates.'),
          );
          if (mounted) context.pop();
        } else {
          showDialog(
              context: context,
              builder: (_) => const ErrorDialog(
                  message: 'Failed to upload photos. Please try again.'));
        }
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      title: 'Upload CI Documents',
      accentColor: AppColors.riderGreen,
      showBottomNav: false,
      navItems: const [],
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _InfoBanner(),
                const SizedBox(height: 16),
                ..._photos.asMap().entries.map((e) => _PhotoCard(
                      photo: e.value,
                      index: e.key,
                      onRemove: () => setState(() => _photos.removeAt(e.key)),
                      onTypeChange: (t) => setState(() =>
                          _photos[e.key] = _photos[e.key].copyWith(type: t)),
                      onCaptionChange: (c) => setState(() =>
                          _photos[e.key] = _photos[e.key].copyWith(caption: c)),
                      typeLabels: _typeLabels,
                      photoTypes: _photoTypes,
                    )),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.riderGreen,
                    side: const BorderSide(color: AppColors.riderGreen),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _addPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Add Photo',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          if (_photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppButton(
                label: 'Upload ${_photos.length} Photo(s)',
                onPressed: _isUploading ? null : _uploadAll,
                isLoading: _isUploading,
                backgroundColor: AppColors.riderGreen,
                icon: Icons.cloud_upload_outlined,
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.riderGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.riderGreen.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.gps_fixed, color: AppColors.riderGreen, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'All photos are GPS-tagged automatically. Add captions to describe each photo for the investigation report.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoCard extends StatefulWidget {
  final _CiPhoto photo;
  final int index;
  final VoidCallback onRemove;
  final ValueChanged<String> onTypeChange;
  final ValueChanged<String> onCaptionChange;
  final Map<String, String> typeLabels;
  final List<String> photoTypes;

  const _PhotoCard({
    required this.photo,
    required this.index,
    required this.onRemove,
    required this.onTypeChange,
    required this.onCaptionChange,
    required this.typeLabels,
    required this.photoTypes,
  });

  @override
  State<_PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<_PhotoCard> {
  late TextEditingController _captionCtrl;

  @override
  void initState() {
    super.initState();
    _captionCtrl = TextEditingController(text: widget.photo.caption);
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Photo ${widget.index + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.riderGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.gps_fixed,
                        color: AppColors.riderGreen, size: 12),
                    SizedBox(width: 4),
                    Text('GPS Tagged',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.riderGreen,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onRemove,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: AppColors.errorLight, shape: BoxShape.circle),
                  child:
                      const Icon(Icons.close, color: AppColors.error, size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: XFilePreview(
                file: widget.photo.file, height: 150, width: double.infinity),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: widget.photo.type,
            decoration: InputDecoration(
              labelText: 'Photo Type',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: widget.photoTypes
                .map((t) => DropdownMenuItem(
                    value: t, child: Text(widget.typeLabels[t] ?? t)))
                .toList(),
            onChanged: (v) {
              if (v != null) widget.onTypeChange(v);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _captionCtrl,
            decoration: InputDecoration(
              labelText: 'Caption (Optional)',
              hintText: 'Describe what this photo shows...',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            maxLines: 2,
            onChanged: widget.onCaptionChange,
          ),
        ],
      ),
    );
  }
}
