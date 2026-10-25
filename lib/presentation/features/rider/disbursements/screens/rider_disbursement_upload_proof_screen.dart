// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
// lib/presentation/features/rider/disbursements/screens/rider_disbursement_upload_proof_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/security/submission_guard.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/validation/delivery_proof_rules.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/image/xfile_preview.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart'
    show kDesktopBreakpoint;
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

  /// Laki (bytes) ng bawat piniling photo — kailangan para mabilis na
  /// ma-recompute ang TOTAL kapag may tinanggal.
  final Map<String, int> _photoBytes = {};

  /// Pinagsamang laki ng lahat ng piniling photo. 5MB ANG LIMIT NG KABUUAN
  /// (hindi kada photo) — tingnan ang [DeliveryProofRules].
  int _totalBytes = 0;
  String? _signatureBase64;

  /// Validation error ng huling piniling photo — inline sa card (hindi lang
  /// transient na snackbar), para kitang-kita kung bakit tinanggihan.
  String? _pickError;
  bool _isSubmitting = false;

  /// Naka-cache na notifier: HINDI na pwedeng gamitin ang `ref` sa `dispose()`
  /// ("Cannot use ref after the widget was disposed"), kaya ito ang tinatawag
  /// doon para tumigil ang location tracking pag-alis ng screen.
  RiderLocationNotifier? _location;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _location = ref.read(riderLocationProvider.notifier);
      _location?.startTracking();
    });
  }

  @override
  void dispose() {
    _location?.stopTracking();
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
    if (picked == null) return;

    // ── Validation bago tanggapin ang photo ──────────────────────────────
    // 1) Uri: image lang (hindi PDF/dokumento o file na walang image mime).
    if (!DeliveryProofRules.isImage(picked.mimeType)) {
      setState(() => _pickError = DeliveryProofRules.notImageMessage);
      return;
    }
    // 2) Laki: max 5MB ang KABUUAN ng lahat ng photo — ipinapakita ang
    //    aktwal na total kapag lumampas.
    final size = await picked.length();
    final totalBytes = _totalBytes + size;
    if (!DeliveryProofRules.isWithinLimit(totalBytes)) {
      setState(() => _pickError =
          DeliveryProofRules.oversizeMessage(totalBytes));
      return;
    }

    setState(() {
      _pickError = null;
      _proofPhotos.add(picked);
      _photoBytes[picked.path] = size;
      _totalBytes += size;
    });
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
          reason: kSubmissionVerificationReason,
        );
    if (!verified || !mounted) return;

    setState(() => _isSubmitting = true);
    // Ang outcome (hindi ang provider state) ang pinagkakatiwalaan ng screen:
    // kung na-dispose ang autoDispose provider habang tumatakbo ang mabigat na
    // upload, ang muling `ref.read(...).error` ay bagong (null) state ang
    // ibabalik — kaya generic na "Failed to upload proof" ang dating lumalabas.
    ProofUploadOutcome outcome;
    try {
      outcome = await ref
          .read(riderDisbursementProvider.notifier)
          .uploadProof(
            disbursementId: widget.disbursementId,
            proofPhotos: List.of(_proofPhotos),
            signatureBase64: _signatureBase64,
          );
    } catch (_) {
      // Hindi inaasahang error — kumpirmahin pa rin sa server bago sabihing
      // failed, dahil ang upload ay maaaring natuloy doon (lost response).
      final submitted = await ref
          .read(riderDisbursementProvider.notifier)
          .verifyProofSubmitted(widget.disbursementId);
      outcome = submitted
          ? const ProofUploadOutcome(success: true, alreadySubmitted: true)
          : const ProofUploadOutcome(
              success: false,
              error: 'Failed to upload proof. Please try again.',
            );
    }
    if (!mounted) return;
    // I-reset AGAD ang spinner bago mag-modal — kahit mag-fail ang dialog,
    // hindi maii-stuck ang screen sa loading state.
    setState(() => _isSubmitting = false);
    if (!mounted) return;

    if (outcome.success) {
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
      final msg = (outcome.error == null || outcome.error!.isEmpty)
          ? 'Failed to upload proof. Please try again.'
          : outcome.error!;
      await showDialog(
        context: context,
        builder: (_) => ErrorDialog(message: msg),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pinapanatili itong buhay habang nakabukas ang screen. Kapag galing sa
    // Dashboard (walang ibang nagmamatyag sa provider), ang autoDispose na
    // provider ay agad na dini-dispose pagkatapos ng `ref.read` — nawawala ang
    // realtime refresh at ang error/submitting state ng submit.
    ref.watch(riderDisbursementProvider);

    // Parehong widgets sa mobile at desktop — ang layout lang ang nag-iiba.
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    // Sa desktop, pinupuno ng photo box ang buong taas ng card (para walang
    // blangkong puwang sa ibaba kapag magkapantay ang dalawang card).
    final photoSection = _buildPhotoSection(fillHeight: isDesktop);
    // Sa desktop, mas mataas ang signature canvas para puno ang card —
    // magkapantay ang taas ng dalawang card (IntrinsicHeight + stretch).
    final signaturePad = _buildSignaturePad(height: isDesktop ? 200 : 150);
    // Walang Cancel sa desktop — nasa sidebar/top bar ang paglabas doon.
    final actions = _buildActions(context, showCancel: !isDesktop);

    return MobileScaffold(
      title: 'Cash on Delivery',
      accentColor: AppColors.riderGreen,
      showBottomNav: false,
      navItems: const [],
      body: isDesktop
          // DESKTOP: DALAWANG COLUMN — Cash on Delivery photos sa KALIWA,
          // Lender Signature sa KANAN — at naka-cap (1080) at nakasentro.
          // Dati, isang column lang na nakaunat sa buong lapad: blangko ang
          // kalahati ng bawat card at sobrang lapad ng signature canvas.
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // IntrinsicHeight + stretch: MAGKAPANTAY ang taas ng
                      // dalawang card (dati, magkaiba ang haba ng puting card).
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 5, child: photoSection),
                            const SizedBox(width: 20),
                            Expanded(flex: 6, child: signaturePad),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Submit + Cancel sa ibaba, naka-align sa KANAN at
                      // makitid lang — hindi nakaunat sa buong lapad.
                      Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: actions,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                photoSection,
                const SizedBox(height: 16),
                signaturePad,
                const SizedBox(height: 24),
                actions,
              ],
            ),
    );
  }

  /// Submit + Cancel — isang column, buong lapad sa mobile at naka-cap (380)
  /// sa desktop (kanang bahagi ng content).
  Widget _buildActions(BuildContext context, {bool showCancel = true}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      // Buong lapad ng 380 na cap sa desktop; sa mobile, buong lapad ng screen.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'Submit',
          onPressed: _isSubmitting ? null : _submit,
          isLoading: _isSubmitting,
          backgroundColor: AppColors.riderGreen,
        ),
        if (showCancel) ...[
          const SizedBox(height: 12),
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
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Text('Cancel'),
          ),
        ],
      ],
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

  /// [fillHeight] = desktop: ang photo box (previews o empty placeholder) ay
  /// nag-e-expand para puno ang card — kung hindi, may mahabang blangkong
  /// puwang sa ibaba kapag pinantay ang taas sa signature card.
  Widget _buildPhotoSection({bool fillHeight = false}) {
    final missingRequired = _proofPhotos.isEmpty;

    final Widget photoBox = _proofPhotos.isNotEmpty
        ? Row(
            crossAxisAlignment: fillHeight
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < _proofPhotos.length; i++) ...[
                if (i > 0) SizedBox(width: 8),
                Expanded(
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: fillHeight
                            ? SizedBox.expand(
                                child: XFilePreview(file: _proofPhotos[i]))
                            : XFilePreview(
                                file: _proofPhotos[i],
                                height: 140,
                                width: double.infinity),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            final removed = _proofPhotos.removeAt(i);
                            _totalBytes -= _photoBytes.remove(removed.path) ?? 0;
                            _pickError = null;
                          }),
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
        : Container(
            width: double.infinity,
            height: fillHeight ? double.infinity : 180,
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
              ],
            ),
          );
    return Container(
      key: const ValueKey('cod_photo_card'),
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
          // Photo box: previews (max 2) o empty placeholder kapag wala. Sa
          // desktop, pinupuno nito ang natitirang taas ng card.
          if (fillHeight) Expanded(child: photoBox) else photoBox,
          if (_pickError != null) ...[
            SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline,
                    size: 14, color: AppColors.error),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _pickError!,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 12),
          // Maliit na Upload + Clear buttons, naka-right align — at sa
          // KALIWA ng row na ito ang "Tap Upload … max 5MB total" na helper
          // text (hindi sa loob ng empty placeholder).
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.max,
            children: [
              if (_proofPhotos.isEmpty)
                Expanded(
                  child: Text(
                    'Tap Upload to add up to 2 photos '
                    '(max ${DeliveryProofRules.maxLabel} total).',
                    style:
                        TextStyle(fontSize: 11, color: context.cTextTertiary),
                  ),
                )
              else
                const Spacer(),
              // Text lang ang Clear — hindi button style.
              TextButton(
                onPressed: _proofPhotos.isEmpty && _pickError == null
                    ? null
                    : () => setState(() {
                          _proofPhotos.clear();
                          _photoBytes.clear();
                          _totalBytes = 0;
                          _pickError = null;
                        }),
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

  Widget _buildSignaturePad({double height = 150}) {
    return Container(
      key: const ValueKey('cod_signature_card'),
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
              // Expanded: sa makitid na screen (o maliit na desktop window) ay
              // nag-w-wrap ang mahabang title sa halip na umapaw.
              Expanded(
                child: Text('Lender Signature (Optional)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: context.cTextPrimary)),
              ),
            ],
          ),
          SizedBox(height: 12),
          SignaturePad(
            height: height,
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
