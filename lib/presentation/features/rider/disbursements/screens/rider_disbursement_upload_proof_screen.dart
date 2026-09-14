// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
// lib/presentation/features/rider/disbursements/screens/rider_disbursement_upload_proof_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/security/submission_guard.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/image/xfile_preview.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/signature_pad.dart';
import '../providers/rider_disbursement_provider.dart';
import '../../location/providers/rider_location_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

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
  static const _maxPhotos = 2;
  final List<XFile> _proofPhotos = [];
  String? _signatureBase64;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(riderLocationProvider.notifier).startTracking();
    });
  }

  @override
  void dispose() {
    ref.read(riderLocationProvider.notifier).stopTracking();
    super.dispose();
  }

  Future<void> _pickPhoto({bool fromCamera = true}) async {
    if (_proofPhotos.length >= _maxPhotos) {
      context.showSnackBarAsToast(
        const SnackBar(
            content: Text('Maximum 2 photos only'),
            backgroundColor: AppColors.error),
      );
      return;
    }
    final picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked != null) {
      setState(() => _proofPhotos.add(picked));
    }
  }

  Future<void> _submit() async {
    if (_proofPhotos.isEmpty) {
      context.showSnackBarAsToast(
        const SnackBar(
            content: Text('Cash on Delivery proof photo is required'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    // Kumpirmasyon bago ang submission: device credential (fingerprint /
    // Face ID / device PIN), o ang app-level MPIN kapag walang password ang
    // phone — at kung wala pang MPIN, hihingin munang i-set ito.
    final verified = await ref.read(submissionGuardProvider).confirm(
          context,
          reason: 'I-verify ang iyong pagkakakilanlan (fingerprint / Face ID, '
              'device PIN, o MPIN) para maisumite ang Cash on Delivery proof.',
        );
    if (!verified || !mounted) return;

    setState(() => _isSubmitting = true);
    bool ok = false;
    String? backendError;
    try {
      ok = await ref
          .read(riderDisbursementProvider.notifier)
          .uploadProof(
            disbursementId: widget.disbursementId,
            proofPhotos: List.of(_proofPhotos),
            signatureBase64: _signatureBase64,
          );
      backendError = ref.read(riderDisbursementProvider).error;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    // I-reset AGAD ang spinner bago mag-modal — kahit mag-fail ang dialog,
    // hindi maii-stuck ang screen sa loading state.
    setState(() => _isSubmitting = false);
    if (!mounted) return;

    if (ok) {
      // Auto-dismiss pattern (gaya sa CI submit): steady 2s modal, tapos
      // diretso sa list. Naka-try/catch para kahit mag-error ang dialog,
      // makakaalis pa rin si rider sa screen (naka-submit na sa backend).
      try {
        await SuccessDialog.showAutoDismiss(
          context,
          title: 'Cash on Delivery Submitted',
          message: 'Proof uploaded and loan released to the lender!',
          buttonText: 'Done',
        );
      } catch (_) {}
      if (!mounted) return;
      context.go(RouteConstants.riderDisbursements);
    } else {
      final msg = (backendError == null || backendError.isEmpty)
          ? 'Failed to upload proof. Please try again.'
          : backendError;
      await showDialog(
        context: context,
        builder: (_) => ErrorDialog(message: msg),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      title: 'Cash on Delivery',
      accentColor: AppColors.riderGreen,
      showBottomNav: false,
      navItems: const [],
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _buildPhotoSection(),
          SizedBox(height: 16),
          _buildSignaturePad(),
          SizedBox(height: 24),
          AppButton(
            label: 'Submit',
            onPressed: _isSubmitting ? null : _submit,
            isLoading: _isSubmitting,
            backgroundColor: AppColors.riderGreen,
          ),
          SizedBox(height: 12),
          OutlinedButton(
            // Cancel = back. Kapag walang ma-pop (hal. deep link), diretso
            // sa disbursements list para hindi ma-stuck sa screen.
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                context.pop();
              } else {
                context.go(RouteConstants.riderDisbursements);
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: context.cTextSecondary,
              side: BorderSide(color: context.cBorder),
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Camera / Gallery picker sheet para sa Upload button.
  Future<void> _pickSource() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.cSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Photo',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: context.cTextPrimary)),
              SizedBox(height: 12),
              ListTile(
                leading:
                    Icon(Icons.camera_alt, color: AppColors.riderGreen),
                title: Text('Camera',
                    style: TextStyle(color: context.cTextPrimary)),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: Icon(Icons.photo_library_outlined,
                    color: AppColors.info),
                title: Text('Gallery',
                    style: TextStyle(color: context.cTextPrimary)),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    await _pickPhoto(fromCamera: choice == 'camera');
  }

  Widget _buildPhotoSection() {
    final missingRequired = _proofPhotos.isEmpty;
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: missingRequired
                ? AppColors.error.withValues(alpha: 0.3)
                : context.cBorder),
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
              Icon(Icons.camera_alt_outlined,
                  color: AppColors.riderGreen, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Cash on Delivery',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: context.cTextPrimary)),
              ),
              // Photo counter (max 2).
              Text('${_proofPhotos.length}/$_maxPhotos',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.cTextTertiary)),
            ],
          ),
          SizedBox(height: 12),
          // Photo box: previews (max 2) o empty placeholder kapag wala.
          if (_proofPhotos.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _proofPhotos.length; i++) ...[
                  if (i > 0) SizedBox(width: 8),
                  Expanded(
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: XFilePreview(
                              file: _proofPhotos[i],
                              height: 140,
                              width: double.infinity),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _proofPhotos.removeAt(i)),
                            child: Container(
                              padding: EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle),
                              child: Icon(Icons.close,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            )
          else
            Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: context.cSurfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.cBorder),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined,
                      size: 40, color: context.cTextTertiary),
                  SizedBox(height: 8),
                  Text('No photo yet',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.cTextSecondary)),
                  SizedBox(height: 2),
                  Text('Tap Upload below to add up to 2 photos',
                      style: TextStyle(
                          fontSize: 12, color: context.cTextTertiary)),
                ],
              ),
            ),
          SizedBox(height: 12),
          // Maliit na Upload + Clear buttons, naka-right align.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.max,
            children: [
              // Text lang ang Clear — hindi button style.
              TextButton(
                onPressed: _proofPhotos.isEmpty
                    ? null
                    : () => setState(() => _proofPhotos.clear()),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  padding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Clear',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              SizedBox(width: 4),
              ElevatedButton.icon(
                onPressed: _pickSource,
                icon: Icon(Icons.upload_rounded, size: 14),
                label: Text('Upload',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.riderGreen,
                  foregroundColor: Colors.white,
                  padding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
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
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
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
              Icon(Icons.draw_outlined, color: AppColors.riderGreen, size: 20),
              SizedBox(width: 8),
              Text('Lender Signature (Optional)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: context.cTextPrimary)),
            ],
          ),
          SizedBox(height: 12),
          SignaturePad(
            height: 150,
            showActionIcons: false,
            // "Signature cleared" feedback: 1 segundo lang (rider flow).
            clearedFeedbackDuration: const Duration(seconds: 1),
            onSignatureChanged: (base64) =>
                setState(() => _signatureBase64 = base64),
          ),
          if (_signatureBase64 != null)
            Padding(
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
