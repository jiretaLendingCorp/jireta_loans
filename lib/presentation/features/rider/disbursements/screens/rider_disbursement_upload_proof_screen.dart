// lib/presentation/features/rider/disbursements/screens/rider_disbursement_upload_proof_screen.dart
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
import '../providers/rider_disbursement_provider.dart';

class RiderDisbursementUploadProofScreen extends ConsumerStatefulWidget {
  final String disbursementId;
  const RiderDisbursementUploadProofScreen(
      {super.key, required this.disbursementId});

  @override
  ConsumerState<RiderDisbursementUploadProofScreen> createState() =>
      _RiderDisbursementUploadProofScreenState();
}

class _RiderDisbursementUploadProofScreenState
    extends ConsumerState<RiderDisbursementUploadProofScreen> {
  final _picker = ImagePicker();
  XFile? _proofPhoto;
  String? _signatureBase64;
  bool _isSubmitting = false;

  Future<void> _pickPhoto({bool fromCamera = true}) async {
    final picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked != null) {
      setState(() => _proofPhoto = picked);
    }
  }

  Future<void> _submit() async {
    if (_proofPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Delivery proof photo is required'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final ok = await ref
          .read(riderDisbursementProvider.notifier)
          .uploadProof(
            disbursementId: widget.disbursementId,
            proofPhoto: _proofPhoto!,
            signatureBase64: _signatureBase64,
          );

      if (mounted) {
        if (ok) {
          await showDialog(
            context: context,
            builder: (_) => const SuccessDialog(
                message: 'Proof uploaded and loan released to the lender!'),
          );
          if (mounted) context.go(RouteConstants.riderDisbursements);
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
      title: 'Upload Delivery Proof',
      accentColor: AppColors.riderGreen,
      showBottomNav: false,
      navItems: const [],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.riderGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.riderGreen.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.riderGreen, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Take a clear photo showing that the cash was handed to the lender. The loan will be released once proof is uploaded.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildPhotoSection(),
          const SizedBox(height: 16),
          _buildSignaturePad(),
          const SizedBox(height: 24),
          AppButton(
            label: 'Submit & Complete Delivery',
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

  Widget _buildPhotoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _proofPhoto == null
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
          const Row(
            children: [
              Icon(Icons.camera_alt_outlined,
                  color: AppColors.riderGreen, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Delivery Proof Photo *',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.textPrimary)),
                    Text('Photo of the cash handed to the lender',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_proofPhoto != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: XFilePreview(
                      file: _proofPhoto!, height: 180, width: double.infinity),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => setState(() => _proofPhoto = null),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 16),
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
                    onTap: _pickPhoto,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PhotoPickerButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    color: AppColors.info,
                    onTap: () => _pickPhoto(fromCamera: false),
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
              Text('Lender Signature (Optional)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Ask the lender to sign as acknowledgement of receipt',
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
                  Icon(Icons.check_circle, color: AppColors.riderGreen, size: 16),
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
  const _PhotoPickerButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

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
