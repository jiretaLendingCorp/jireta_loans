// lib/presentation/features/rider/collections/screens/rider_upload_proof_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/image/xfile_preview.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/signature_pad.dart';
import '../providers/rider_collection_provider.dart';

class RiderUploadProofScreen extends ConsumerStatefulWidget {
  final String assignmentId;
  const RiderUploadProofScreen({super.key, required this.assignmentId});

  @override
  ConsumerState<RiderUploadProofScreen> createState() =>
      _RiderUploadProofScreenState();
}

class _RiderUploadProofScreenState
    extends ConsumerState<RiderUploadProofScreen> {
  final _picker = ImagePicker();
  XFile? _proofPhoto;
  XFile? _scenePhoto;
  String? _signatureBase64;
  bool _isSubmitting = false;

  Future<void> _pickImage(
      {required bool isProof, bool fromCamera = true}) async {
    final picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked != null) {
      setState(() {
        if (isProof) {
          _proofPhoto = picked;
        } else {
          _scenePhoto = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (_proofPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Payment proof photo is required'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final ok = await ref.read(riderCollectionProvider.notifier).uploadProof(
            assignmentId: widget.assignmentId,
            proofPhoto: _proofPhoto!,
            scenePhoto: _scenePhoto,
            signatureBase64: _signatureBase64,
          );

      if (mounted) {
        if (ok) {
          await showDialog(
            context: context,
            builder: (_) => const SuccessDialog(
                message: 'Proof uploaded and collection completed!'),
          );
          if (mounted) context.go(RouteConstants.riderCollections);
        } else {
          showDialog(
            context: context,
            builder: (_) => const ErrorDialog(
                message: 'Failed to upload proof. Please try again.'),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      title: 'Upload Proof',
      accentColor: AppColors.riderGreen,
      showBottomNav: false,
      navItems: const [],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoBanner(),
          const SizedBox(height: 16),
          _buildPhotoSection(
            title: 'Payment Proof Photo *',
            subtitle: 'Take a clear photo of the payment receipt or cash',
            icon: Icons.receipt_long_outlined,
            photo: _proofPhoto,
            onCamera: () => _pickImage(isProof: true),
            onGallery: () => _pickImage(isProof: true, fromCamera: false),
            required: true,
          ),
          const SizedBox(height: 16),
          _buildSignaturePad(),
          const SizedBox(height: 16),
          _buildPhotoSection(
            title: 'Scene Photo (Optional)',
            subtitle: 'Photo of the collection scene for verification',
            icon: Icons.camera_outdoor_outlined,
            photo: _scenePhoto,
            onCamera: () => _pickImage(isProof: false),
            onGallery: () => _pickImage(isProof: false, fromCamera: false),
            required: false,
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Submit & Complete Collection',
            onPressed: _isSubmitting ? null : _submit,
            isLoading: _isSubmitting,
            backgroundColor: AppColors.riderGreen,
            icon: Icons.cloud_upload_outlined,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Text('Skip & Complete Later'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
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
              'Your GPS coordinates are automatically captured and attached to all uploaded photos.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required XFile? photo,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
    required bool required,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: required && photo == null
                ? AppColors.error.withValues(alpha: 0.3)
                : AppColors.border),
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
              Icon(icon, color: AppColors.riderGreen, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.textPrimary)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (photo != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: XFilePreview(file: photo, height: 180, width: double.infinity),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      if (required) {
                        _proofPhoto = null;
                      } else {
                        _scenePhoto = null;
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.riderGreen,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('GPS Tagged',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _PhotoPickerButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    color: AppColors.riderGreen,
                    onTap: onCamera,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PhotoPickerButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    color: AppColors.info,
                    onTap: onGallery,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSignaturePad() {
    return Container(
      padding: const EdgeInsets.all(16),
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
          const Row(
            children: [
              Icon(Icons.draw_outlined, color: AppColors.riderGreen, size: 20),
              SizedBox(width: 8),
              Text('Borrower Signature',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Ask the borrower to sign below',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          SignaturePad(
            height: 150,
            onSignatureChanged: (base64) =>
                setState(() => _signatureBase64 = base64),
          ),
          if (_signatureBase64 != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      color: AppColors.riderGreen, size: 16),
                  SizedBox(width: 6),
                  Text('Signature captured',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.riderGreen,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoPickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PhotoPickerButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
