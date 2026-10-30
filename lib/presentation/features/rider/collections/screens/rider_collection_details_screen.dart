// ignore_for_file: unused_element, prefer_const_constructors, prefer_const_literals_to_create_immutables
// lib/presentation/features/rider/collections/screens/rider_collection_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/constants/route_constants.dart';
// Kapareho ng CI Task uploads: iisang 5MB limit at label sa buong app.
import '../../../../../core/validation/ci_evidence_rules.dart';
import '../../../../../core/security/submission_guard.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/utils/input_formatters.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/image/xfile_preview.dart';
// Isang breakpoint lang ang buong app para sa desktop layout.
import '../../../../shared/widgets/layout/web_scaffold.dart'
    show kDesktopBreakpoint, WebScaffold;
import '../../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/signature_pad.dart';
import '../providers/rider_collection_provider.dart';
import '../../../../../core/utils/logger.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class RiderCollectionDetailsScreen extends ConsumerStatefulWidget {
  final String collectionId;
  const RiderCollectionDetailsScreen({super.key, required this.collectionId});

  @override
  ConsumerState<RiderCollectionDetailsScreen> createState() =>
      _RiderCollectionDetailsScreenState();
}

class _RiderCollectionDetailsScreenState
    extends ConsumerState<RiderCollectionDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _imagePicker = ImagePicker();
  /// Payment proof photos — ISA o DALAWA, sa IISANG card. Ang unang photo ang
  /// ipinapadala bilang `proof_photo`, ang pangalawa (kung meron) bilang
  /// `scene_photo`. Basta ang KABUUANG laki ng dalawa ay hindi lalampas sa 5MB
  /// (hindi per photo).
  final List<XFile> _proofPhotos = <XFile>[];
  final List<int> _proofSizes = <int>[];

  /// Inline validation sa Payment Proof card — kapag lumampas sa 5MB TOTAL.
  String? _proofError;

  /// Kabuuang laki (bytes) ng lahat ng napiling proof — ito ang sinusuri laban
  /// sa 5MB, at ito rin ang ipinapakita sa card.
  int _proofTotalBytes = 0;

  String? _signatureBase64;
  bool _isSubmitting = false;

  /// Tapos na ba ang aming sariling load ng details. Habang false pa, loader
  /// ang ipinapakita — kung hindi, may isang frame na "Collection not found"
  /// na sumasabit bago dumating ang totoong data (yung "splash" na nakikita).
  bool _detailsResolved = false;

  // Step labels — dating Step 2 (Collect) ay pinagsama na sa Step 1, kaya 3
  // steps na lang ang wizard.
  static const _steps = ['Details', 'Proof', 'Review'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _amountCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Loader muna habang wala pa ang sagot ng server — ang "Collection not
      // found" ay ipapakita lang kapag tapos na talaga ang pag-load at wala pa
      // ring nahanap (hindi na sasabit sa unang frame).
      await ref
          .read(riderCollectionProvider.notifier)
          .loadDetails(widget.collectionId);
      if (mounted) setState(() => _detailsResolved = true);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _goToStep(int index) {
    if (index < 0 || index >= _tabController.length) return;
    _tabController.animateTo(index);
  }

  /// Auto-next disabled per request: stay at Details (step 1) first.
  /// Rider must manually tap "Continue to Collect".
  void _maybeAutoAdvance(CollectionAssignmentModel col) {
    return;
  }

  /// Pinakamalaking pinapayagang KABUUANG laki ng proof photos — KAPAREHO ng
  /// CI Task uploads (`CiEvidenceRules`): 5MB. Isa O dalawang photo ang
  /// pinapayagan, basta ang suma ng dalawa ay pasok sa 5MB. Base64 ang
  /// ipapadala sa server (≈33% na mas malaki), kaya dito pa lang sa pagpili ay
  /// hinaharangan na ang sobrang laki; hindi na hihintayin ang failure sa
  /// upload.
  static const int _maxProofBytes = CiEvidenceRules.maxBytes;

  /// Idinaragdag ang piniling photo sa Payment Proof card — 2 photos lang ang
  /// tinatanggap, at ang KABUUANG laki ng lahat ay dapat ≤ 5MB. Kapag sobra,
  /// inline error + toast, at HINDI itatakda ang photo.
  Future<void> _addProofPhoto(XFile picked) async {
    if (_proofPhotos.length >= 2) return;
    final size = await picked.length();
    final total = _proofTotalBytes + size;
    if (!mounted) return;
    if (total > _maxProofBytes) {
      final totalLabel = CiEvidenceRules.sizeLabel(total);
      setState(() {
        _proofError =
            'Photos would total $totalLabel — over the ${CiEvidenceRules.maxLabel} '
            'limit. Remove a photo or choose a smaller one.';
      });
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(
            'Total upload is too large ($totalLabel). Maximum is '
            '${CiEvidenceRules.maxLabel} for 1–2 photos.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() {
      _proofPhotos.add(picked);
      _proofSizes.add(size);
      _proofTotalBytes = total;
      _proofError = null;
    });
  }

  Future<void> _pickImage({bool fromCamera = true}) async {
    if (_proofPhotos.length >= 2) return;
    final picked = await _imagePicker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked == null || !mounted) return;
    await _addProofPhoto(picked);
  }

  void _removeProofPhoto(int index) {
    if (index < 0 || index >= _proofPhotos.length) return;
    setState(() {
      _proofPhotos.removeAt(index);
      _proofSizes.removeAt(index);
      _proofTotalBytes = _proofSizes.fold(0, (sum, size) => sum + size);
      _proofError = null;
    });
  }

  /// Preview ng na-upload na proof photo — buong screen, pwedeng i-zoom.
  /// May back arrow sa itaas para makabalik sa Proof step.
  void _viewProofPhoto(int index) {
    if (index < 0 || index >= _proofPhotos.length) return;
    _viewPhoto(_proofPhotos[index], 'Payment Proof ${index + 1}');
  }

  void _viewPhoto(XFile? file, String title) {
    if (file == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (viewerContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => Navigator.of(viewerContext).pop(),
            ),
            title: Text(title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: XFilePreview(file: file, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showProofSourceSheet() => _showSourceSheet();

  /// Pinipindot ng rider ang maliit na "Upload" button sa photo card — dito
  /// pipiliin kung Camera o Gallery.
  Future<void> _showSourceSheet() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.cSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.camera_alt, color: AppColors.riderGreen),
              title: const Text('Take Photo'),
              subtitle: const Text('Camera'),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.info),
              title: const Text('Choose from Gallery'),
              subtitle: const Text('Gallery'),
              onTap: () => Navigator.of(sheetContext).pop('gallery'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    if (source == 'camera') {
      await _pickImage();
    } else {
      await _pickImage(fromCamera: false);
    }
  }

  /// True kapag ang huling error ay ang backend guard na "wala pang verified
  /// payment" (PAYMENT_NOT_RECORDED, 409) mula sa `fn=upload-proof`.
  bool _isPaymentNotRecordedError() {
    final err = (ref.read(riderCollectionProvider).error ?? '').toLowerCase();
    return err.contains('record the collected amount');
  }

  /// Step 1 → Step 2. Validation lang ito — HINDI pa nire-record sa server ang
  /// amount dito.
  ///
  /// Business rule: ang `collections-manage?fn=record` ay (a) gumagawa ng
  /// verified `payments` row (bumababa agad ang balanse ng loan),
  /// (b) nagpapasa ng assignment sa `in_progress` + `amount_collected`, at
  /// (c) nagpapadala ng "Payment Received" push sa lender. Kaya kung dito pa
  /// ito isasagawa, makikita na agad ng Head Manager / Employee ang koleksyon
  /// kahit hindi pa na-submit ng rider. Sa Step 3 (Review → Submit) na lang
  /// ito isinasagawa, sabay ng proof upload — nasa `_amountCtrl` lang muna ang
  /// halaga at walang nakikitang record ang HM / Employee.
  void _validateAmountAndNext() {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      context.showSnackBarAsToast(
          const SnackBar(content: Text('Please enter a valid amount')));
      return;
    }
    _goToStep(1);
  }

  void _validateProofAndNext(CollectionAssignmentModel col) {
    if (_proofPhotos.isEmpty && col.status != 'completed') {
      context.showSnackBarAsToast(
          const SnackBar(content: Text('Payment proof photo is required')));
      return;
    }
    _goToStep(2);
  }

  Future<void> _submitReview(CollectionAssignmentModel col) async {
    // If already completed, just go back
    if (col.status == 'completed') {
      context.pop();
      return;
    }

    // If amount not yet recorded and user entered amount in this flow, record it first
    final hasCollectedAmount = col.amountCollected != null;
    double? pendingAmount;
    if (!hasCollectedAmount) {
      pendingAmount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
      if (pendingAmount == null || pendingAmount <= 0) {
        context.showSnackBarAsToast(
          const SnackBar(
              content: Text('Amount is missing — go back to Step 1')),
        );
        _goToStep(0);
        return;
      }
    }

    if (_proofPhotos.isEmpty) {
      context.showSnackBarAsToast(const SnackBar(
          content: Text('Please add payment proof in Proof step')));
      _goToStep(1);
      return;
    }

    final amountText = pendingAmount?.toCurrency ??
        col.amountCollected?.toCurrency ??
        _amountCtrl.text;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Submit Collection',
        message:
            'Record $amountText as collected from lender and submit with proof?',
        confirmText: 'Yes',
        confirmColor: AppColors.riderGreen,
      ),
    );
    if (confirmed != true || !mounted) return;

    // Kumpirmasyon bago i-record/submit ang collection: device credential
    // (fingerprint / Face ID / device PIN), o ang app-level MPIN kapag walang
    // password ang phone — at kung wala pang MPIN, hihingin munang i-set ito.
    final verified = await ref.read(submissionGuardProvider).confirm(
          context,
          reason: kSubmissionVerificationReason,
        );
    if (!verified || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      // Autoritatibong fetch muna para hindi stale ang status/amount.
      //
      // DATE: `loadDetails(silent: true)` — ngunit ang unang hakbang nito ay
      // tumitingin sa NAKA-CACHE na listahan, kaya kung may lumang kopya ang
      // rider list, ang `amountCollected`/`status` mula roon ang gagamitin ng
      // submit: puwedeng maling amount ang mairecord (o maling desisyon kung
      // kailangan pang mag-record) kahit tama ang nakikita/nai-type ng rider.
      // Ang `fetchFresh` ay direktang kumukuha sa server.
      // Hindi na kumukuha ng `fetchFresh` bago mag-submit: ang amount mula sa
      // Step 1 ang basehan at ang backend (idempotent + self-healing) ang
      // autoridad. Ang dating pre-fetch ay dagdag na round trip na may kasamang
      // pag-sign ng 3 proof URL — isa ito sa mga dahilan ng mabagal na loading.
      final fresh = col;

      // Business rule: kailangan may VERIFIED payment row bago ma-upload ang
      // proof (binabantayan ito ng backend na `fn=upload-proof`).
      //
      // Dati, ang basehan ay ang status (`in_progress` = "na-record na") kaya
      // ni-skip ang record at dumiretso sa proof. Pero puwedeng maiwan sa
      // `in_progress` ang assignment kahit wala nang verified payment (hal.
      // na-reverse ang payment sa HM side) — doon, laging "Record the collected
      // amount first before uploading proof" ang error at stuck ang rider.
      //
      // Ngayon, laging sinisiguro ang record bago ang proof. Idempotent na ang
      // backend kapag may verified payment na para sa assignment, kaya safe ito
      // kahit i-retry ng rider ang submit.
      final recordAmount = pendingAmount ??
          double.tryParse(_amountCtrl.text.replaceAll(',', '')) ??
          fresh.amountCollected;
      if (fresh.status != 'completed' &&
          (recordAmount == null || recordAmount <= 0)) {
        // Walang amount na maipapasa (hal. na-clear ang field at walang
        // na-record na sa server) — huwag nang subukan ang proof, siguradong
        // PAYMENT_NOT_RECORDED (409) lang ang aabutin nito.
        if (mounted) {
          context.showSnackBarAsToast(
            const SnackBar(
                content: Text('Amount is missing — go back to Step 1')),
          );
          _goToStep(0);
        }
        return;
      }
      // WALANG hiwalay na `record` call dito. Ang `fn=upload-proof` (ibaba) ang
      // nagse-save ng LAHAT sa isang request: kung wala pang verified payment,
      // siya na mismo ang nagre-record ng amount bago mag-complete (business
      // rule: sa Step 3 Submit nase-save ang amount at proof). Mas mabilis
      // (isang POST), at walang kalahating-saved na estado.

      // Now upload proof — kasama ang amount: kapag nawala/na-reverse ang
      // verified payment sa server, ito na mismo ang magre-record nito
      // (self-heal) kaya hindi na lalabas ang "Record the collected amount
      // first before uploading proof" at hindi na maiiwan sa in_progress.
      String? proofStatus =
          await ref.read(riderCollectionProvider.notifier).uploadProof(
                assignmentId: widget.collectionId,
                proofPhoto: _proofPhotos.first,
                scenePhoto:
                    _proofPhotos.length > 1 ? _proofPhotos[1] : null,
                signatureBase64: _signatureBase64,
                amountCollected: recordAmount,
                notes: _notesCtrl.text.trim().isEmpty
                    ? null
                    : _notesCtrl.text.trim(),
              );

      // Recovery: kapag PAYMENT_NOT_RECORDED (409) ang isinagot ng backend —
      // nawala/na-reverse ang verified payment habang in_progress pa ang
      // assignment — i-record muna ang amount tapos i-retry ang proof nang
      // isang beses. Kung hindi, mananatiling stuck ang rider sa parehong
      // "Record the collected amount first before uploading proof" error.
      if (proofStatus == null && _isPaymentNotRecordedError()) {
        final retryAmount = recordAmount ??
            double.tryParse(_amountCtrl.text.replaceAll(',', ''));
        if (retryAmount != null && retryAmount > 0) {
          final okRecord =
              await ref.read(riderCollectionProvider.notifier).recordCollection(
                    assignmentId: widget.collectionId,
                    amountCollected: retryAmount,
                    notes: _notesCtrl.text.trim().isEmpty
                        ? null
                        : _notesCtrl.text.trim(),
                  );
          if (okRecord) {
            proofStatus =
                await ref.read(riderCollectionProvider.notifier).uploadProof(
                      assignmentId: widget.collectionId,
                      proofPhoto: _proofPhotos.first,
                      scenePhoto: _proofPhotos.length > 1
                          ? _proofPhotos[1]
                          : null,
                      signatureBase64: _signatureBase64,
                      amountCollected: retryAmount,
                      notes: _notesCtrl.text.trim().isEmpty
                          ? null
                          : _notesCtrl.text.trim(),
                    );
          }
        }
      }

      if (!mounted) return;

      // ── Verification bago mag-claim ng success ─────────────────────────
      // Ang `fn=upload-proof` ay nagbabalik na ng `status: 'completed'` —
      // hindi na kailangan ng hiwalay na `get` (mabigat ito: may kasamang
      // pag-sign ng 3 proof URL) para kumpirmahin ang submission. Ang fallback
      // na verification ay para lang sa LUMANG deployment na hindi pa
      // nagbabalik ng `status`.
      if (proofStatus == null &&
          ref.read(riderCollectionProvider).error == null) {
        final submitted = await _verifyCompletedOnServer();
        if (!mounted) return;
        if (submitted) proofStatus = 'completed';
      }

      // Business rule (BINAGO): `completed` NA AGAD ang koleksyon pagkatapos
      // mag-submit ng rider — walang approval ng HM/Employee, at agad na ring
      // bumaba ang loan balance. Tinatanggap pa rin ang `pending_approval` para
      // sa lumang data/deployment.
      if (proofStatus == 'completed' || proofStatus == 'pending_approval') {
        // Success: 2-segundong confirmation modal, tapos deretso na sa Home
        // (rider dashboard) — hindi na bumabalik sa listahan o wizard.
        await SuccessDialog.showAutoDismiss(
          context,
          title: 'Collection Recorded',
          message:
              'The collection was recorded and posted to the lender\'s loan balance.',
          buttonText: 'Done',
          duration: const Duration(seconds: 2),
        );
        if (mounted) context.go(RouteConstants.riderDashboard);
      } else {
        AppLogger.w(
            '[CollectionSubmit] hindi nag-complete ang assignment — id=${widget.collectionId}');
        final errMsg = ref.read(riderCollectionProvider).error ??
            'Failed to upload proof. Please tap Submit to try again.';
        await showDialog(
            context: context, builder: (_) => ErrorDialog(message: errMsg));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Kumpirmahin sa server na `completed` na ang assignment pagkatapos ng
  /// `upload-proof`. Hindi na nagsasabi ng success ang UI kapag hindi ito totoo.
  Future<bool> _verifyCompletedOnServer() async {
    final status = await ref
        .read(riderCollectionProvider.notifier)
        .fetchStatus(widget.collectionId);
    return status == 'completed' || status == 'pending_approval';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCollectionProvider);
    final col = state.selectedCollection;

    // Sync amount/notes if loaded and controllers empty
    if (col != null) {
      // Ang halagang dapat kolektahin ay:
      //  1) ang NAKATALANG amount (kapag in_progress/completed na ang collection), o
      //  2) ang AMOUNT NA HININGI / nakatakda ng staff (`requested_amount`) — para sa
      //     cash-on-delivery na ang system na ang may alam kung magkano ang dapat
      //     kolektahin; hindi na kailangang i-type muli ng rider at hindi na blangko
      //     (dati, ang requested amount ay hindi ipinapakita, kaya "hindi na-colect"
      //     ang tamang halaga kapag hindi ito na-type nang eksakto).
      final suggestedAmount = col.amountCollected ?? col.requestedAmount;
      if (_amountCtrl.text.isEmpty && suggestedAmount != null) {
        _amountCtrl.text =
            ThousandsSeparatorInputFormatter.format(suggestedAmount);
      }
      // HINDI na kinokopya sa editable na field ang `col.notes` (ang notes na
      // ini-assign ng HM/Employee): hindi ito pag-aari ng rider, kaya basahin
      // lang ito sa "Assigned Notes" na tile. Ang `_notesCtrl` ay para sa
      // SARILING note ng rider (napupunta sa `payments.notes`, hiwalay sa
      // `collection_assignments.collection_notes`).
    }

    try {
      // Show provider error (e.g. parseBool failure) explicitly instead of silent
      // "not found". Hindi rin ito dapat lumabas bago pa tayo nag-request ng
      // details — baka error lang ito ng list load sa dating screen.
      if (state.error != null &&
          col == null &&
          !state.isLoading &&
          _detailsResolved) {
        return Scaffold(
          backgroundColor: context.cPageBg,
          appBar: AppBar(
            backgroundColor: context.headerColor(AppColors.riderGreen),
            foregroundColor: Colors.white,
            title: Text('Collection',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  SizedBox(height: 12),
                  Text('Failed to load collection',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text(state.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: context.cTextSecondary)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(riderCollectionProvider.notifier)
                        .loadDetails(widget.collectionId),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.riderGreen),
                    child: Text('Retry', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // ISANG body lang ito para sa mobile at desktop — ang shell lang ang
      // pinag-iba (tingnan sa ibaba).
      final Widget pageBody = state.isLoading || !_detailsResolved
          ? const ShimmerLoader()
          : col == null
              ? const Center(child: Text('Collection not found'))
              : Builder(
                  builder: (context) {
                    try {
                      // ── Fix: completed/declined collections are read-only.
                      // Showing the 4-step wizard for a completed collection
                      // is confusing (user reported "parang wizard na step").
                      // For completed/declined/failed, show a simple details
                      // receipt instead of the wizard.
                      final isReadOnly = _isReadOnlyStatus(col.status);
                      if (isReadOnly) {
                        return Column(
                          children: [
                            Expanded(
                              child: col.status == 'completed'
                                  ? _buildCompletedBody(col)
                                  : col.status == 'pending_approval'
                                      ? _buildPendingApprovalBody(col)
                                      : _buildDeclinedBody(col),
                            ),
                            _buildReadOnlyFooter(col),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _buildDetailsTab(col),
                                _desktopCap(_buildProofTab(col)),
                                _desktopCap(_buildReviewTab(col)),
                              ],
                            ),
                          ),
                          // Accept/Decline — naka-pin sa baba ng mobile view
                          // habang 'assigned' pa (bago i-accept).
                          if (col.status == 'assigned')
                            _buildAcceptDeclineBar(col),
                          // Back + Next — naka-pin sa baba sa Step 1 kapag
                          // tuloy na ang koleksyon (accepted/in_progress).
                          // Ang Back + Submit ay nasa loob ng Review tab.
                        ],
                      );
                    } catch (e, st) {
                      // Log full stack for debugging String vs bool
                      debugPrint('RiderCollectionDetails build error: $e');
                      debugPrint(st.toString());
                      return Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                Icon(Icons.bug_report,
                                    color: AppColors.error, size: 36),
                                SizedBox(height: 8),
                                Text('Build error: $e',
                                    style: TextStyle(
                                        color: AppColors.error, fontSize: 12)),
                                SizedBox(height: 8),
                                Text(st.toString(),
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: context.cTextTertiary)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  },
                );

      final showStep = col != null && !_isReadOnlyStatus(col.status);
      final stepLabel =
          'Step ${_tabController.index + 1} of ${_steps.length}: ${_steps[_tabController.index]}';

      // DESKTOP: huwag mawala ang SIDE NAV BAR kapag binuksan ang collection
      // (mula sa dashboard card o sa Collections tab). `WebScaffold` ang
      // nagbibigay ng rider sidebar + top bar. Dati, laging ang custom na
      // `Scaffold` sa ibaba ang ginagamit — punong-puno ang page at wala nang
      // paraan para lumipat ng pahina maliban sa back button.
      if (MediaQuery.sizeOf(context).width >= kDesktopBreakpoint) {
        return WebScaffold(
          title: 'Collection',
          roleOverride: AppConstants.roleRider,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textSecondary, size: 20),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go(RouteConstants.riderCollections);
              }
            },
          ),
          actions: [
            // Ang step label at status chip ay nasa mobile AppBar; sa desktop,
            // sa top bar sila para hindi mawala ang konteksto.
            if (showStep)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  stepLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: context.cTextSecondary),
                ),
              ),
            if (col != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: StatusBadge(
                    status: col.status,
                    // Rider-facing term — huwag "Failed" (tingnan ang
                    // `CollectionAssignmentModel.statusLabel`).
                    labelOverride:
                        col.status == 'failed' ? 'Uncollected' : null),
              ),
          ],
          body: pageBody,
        );
      }

      return Scaffold(
        backgroundColor: context.cPageBg,
        appBar: AppBar(
          backgroundColor: context.headerColor(AppColors.riderGreen),
          foregroundColor: Colors.white,
          elevation: 0,
          // Step label ay kasama na sa header, sa tabi ng "Collection" —
          // wala nang hiwalay na step bar sa ilalim ng AppBar.
          title: Row(
            children: [
              const Text('Collection',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              if (showStep)
                Expanded(
                  child: Padding(
                    // Walang left padding — para naka-usog nang bahagya sa
                    // kaliwa ang step label (hindi gitna ng buong espasyo).
                    padding: const EdgeInsets.only(right: 24),
                    child: Text(
                      stepLabel,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            if (col != null)
              Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                      child: StatusBadge(
                          status: col.status,
                          small: false,
                          // Rider-facing term — huwag "Failed".
                          labelOverride:
                              col.status == 'failed' ? 'Uncollected' : null,
                          // Green AppBar: keep the status readable.
                          onDark: true))),
          ],
        ),
        body: pageBody,
      );
    } catch (e, st) {
      debugPrint('RiderCollectionDetails outer build error: $e');
      debugPrint(st.toString());
      return Scaffold(
        backgroundColor: context.cPageBg,
        appBar: AppBar(
            backgroundColor: context.headerColor(AppColors.riderGreen),
            foregroundColor: Colors.white,
            title: Text('Collection')),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Icon(Icons.bug_report, color: AppColors.error, size: 36),
                  SizedBox(height: 8),
                  Text('Outer build error: $e',
                      style: TextStyle(color: AppColors.error, fontSize: 12)),
                  SizedBox(height: 8),
                  Text(st.toString(),
                      style: TextStyle(
                          fontSize: 10, color: context.cTextTertiary)),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  /// Completed / pending-approval / rejected / declined / failed collections are
  /// read-only — walang 4-step wizard, kaya walang step label sa header.
  ///
  /// Business rule: kapag naka-submit na ang rider (`pending_approval`), hindi
  /// na siya dapat mag-record o mag-upload muli — naghihintay na ng approval ng
  /// Head Manager/Employee.
  bool _isReadOnlyStatus(String status) =>
      status == 'completed' ||
      status == 'pending_approval' ||
      status == 'rejected' ||
      status == 'declined' ||
      status == 'failed';

  /// Read-only receipt habang nakabinbin ang approval ng HM/Employee.
  Widget _buildPendingApprovalBody(CollectionAssignmentModel col) {
    final amount = col.amountCollected ?? 0;
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.warning,
                AppColors.warning.withValues(alpha: 0.75)
              ]),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Column(
              children: [
                Icon(Icons.hourglass_top_rounded,
                    size: 42, color: Colors.white),
                SizedBox(height: 10),
                Text('Awaiting Approval',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text(
                  amount.toCurrency,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 6),
                Text(
                  'The Head Manager or Employee will verify that the cash was received. '
                  'The loan balance is only reduced once approved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Read-only footer for completed/declined ───────────────────────────────
  Widget _buildReadOnlyFooter(CollectionAssignmentModel col) {
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    final hPad = isDesktop ? 28.0 : 16.0;
    return Container(
      padding: EdgeInsets.fromLTRB(hPad, 10, hPad, isDesktop ? 20 : 16),
      decoration: BoxDecoration(
        color: context.cSurface,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      // Sa desktop, naka-cap (1080 — kapareho ng receipt sa itaas) at nasa
      // KANAN ang Done button; hindi na ito nakaunat sa buong lapad. Sa mobile,
      // buong lapad pa rin.
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 1080 : 1240),
          child: Align(
            alignment:
                isDesktop ? Alignment.centerRight : Alignment.center,
            child: SizedBox(
              width: isDesktop ? 380 : double.infinity,
              child: ElevatedButton(
                onPressed: () => context.pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: col.status == 'completed'
                      ? AppColors.riderGreen
                      : context.cTextSecondary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  col.status == 'completed' ? 'Done' : 'Back to Collections',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedBody(CollectionAssignmentModel col) {
    final schedule = col.loanSchedule;
    final amountDue = (schedule?['amount_due'] as num?)?.toDouble() ??
        (schedule?['installment_amount'] as num?)?.toDouble() ??
        0;
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    // Parehong cards sa mobile at desktop — ang layout lang ang nag-iiba.
    final successCard = _completedSuccessCard(col);
    final lenderCard = _completedLenderCard(col);
    final collectionCard = _completedCollectionCard(col, schedule, amountDue);
    final locationCard = _completedLocationCard(col);
    final note = _completedNoteBanner();

    if (!isDesktop) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            successCard,
            SizedBox(height: 14),
            lenderCard,
            SizedBox(height: 12),
            collectionCard,
            if (locationCard != null) ...[
              SizedBox(height: 12),
              locationCard,
            ],
            SizedBox(height: 20),
            note,
            SizedBox(height: 16),
          ],
        ),
      );
    }

    // DESKTOP: DALAWANG column — success receipt sa KALIWA, ang mga detalye
    // (lender, collection, location) sa KANAN — at naka-cap (1080) at
    // nakasentro ang buong receipt. Dati, isang column lang na nakaunat sa
    // buong lapad: blangko ang kanang kalahati ng bawat info row at sobrang
    // lapad ng berdeng banner.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    successCard,
                    const SizedBox(height: 16),
                    note,
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    lenderCard,
                    const SizedBox(height: 12),
                    collectionCard,
                    if (locationCard != null) ...[
                      const SizedBox(height: 12),
                      locationCard,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Berdong success receipt (halaga + oras ng pagkumpleto).
  Widget _completedSuccessCard(CollectionAssignmentModel col) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.riderGreen, AppColors.riderGreenDark]),
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Column(
        children: [
          Icon(Icons.verified, size: 42, color: Colors.white),
          SizedBox(height: 10),
          Text('Collection Completed',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              col.amountCollected != null
                  ? col.amountCollected!.toCurrency
                  : '₱0.00',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900),
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Amount collected from lender',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
          ),
          if (col.completedAt != null) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                DateFormat('MMM d, yyyy  •  h:mm a').format(col.completedAt!),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Lender Information card ng completed receipt.
  Widget _completedLenderCard(CollectionAssignmentModel col) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.cBorder)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // `cBrandGreen` para manatiling visible sa dark mode.
                Icon(Icons.person_outline,
                    color: context.cBrandGreen, size: 18),
                SizedBox(width: 8),
                Text('Lender Information',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
            SizedBox(height: 14),
            _InfoTile(
                'Name', col.lenderName.isEmpty ? 'N/A' : col.lenderName),
            _InfoTile(
                'Loan #', col.loanNumber.isEmpty ? 'N/A' : col.loanNumber),
            _InfoTile(
                'Phone',
                (col.loanSchedule?['loan']?['lender_profiles']?['users']
                        ?['phone_number'] as String?) ??
                    (col.lenderPhone.isEmpty ? 'N/A' : col.lenderPhone)),
            if (col.lenderAddresses.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 140,
                      child: Text('Address',
                          style: TextStyle(
                              fontSize: 12, color: context.cTextSecondary))),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: col.lenderAddresses.take(2).map((a) {
                        final m = a as Map<String, dynamic>;
                        final full = [
                          m['street'],
                          m['barangay'],
                          m['city'],
                          m['province']
                        ]
                            .where((e) => e != null && (e as String).isNotEmpty)
                            .join(', ');
                        // Address value sa KANAN ng label — pareho ng
                        // alignment ng ibang info rows (walang chip).
                        return Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Text(full.isEmpty ? 'N/A' : full,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.cTextPrimary)),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Collection card ng completed receipt — dating "Collection Summary".
  Widget _completedCollectionCard(CollectionAssignmentModel col,
      Map<String, dynamic>? schedule, double amountDue) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.cBorder)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined,
                    color: AppColors.riderGreen, size: 18),
                SizedBox(width: 8),
                Text('Collection',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
            Divider(height: 20),
            _InfoTile('Due Date', schedule?['due_date'] ?? 'N/A'),
            _InfoTile(
                'Period',
                'Period ${schedule?['period_number'] ?? schedule?['installment_number'] ?? '—'}'),
            // Hiningi ng lender (`requested_amount`), hindi ang default na
            // installment due.
            _InfoTile(
                'Requested Amount',
                col.requestedAmount != null
                    ? col.requestedAmount!.toCurrency
                    : amountDue.toCurrency),
            _InfoTile(
                'Amount Collected', col.amountCollected?.toCurrency ?? '—'),
            _InfoTile('Status', col.statusLabel),
            if (col.completedAt != null)
              _InfoTile('Completed',
                  DateFormat('MMM d, yyyy h:mm a').format(col.completedAt!)),
            if (col.collectionSchedule != null)
              _InfoTile('Scheduled',
                  DateFormat('MMM d, yyyy h:mm a')
                      .format(col.collectionSchedule!)),
            if (col.notes != null && col.notes!.isNotEmpty)
              _InfoTile('Assigned Notes', col.notes!),
            if (col.idempotencyKey != null)
              _InfoTile('Ref', col.idempotencyKey!),
          ],
        ),
      ),
    );
  }

  /// Collection Location card — `null` kapag walang GPS coordinates.
  Widget? _completedLocationCard(CollectionAssignmentModel col) {
    if (col.locationLat == null || col.locationLng == null) return null;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.cBorder)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on_outlined,
                    color: AppColors.riderGreen, size: 18),
                SizedBox(width: 8),
                Text('Collection Location',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
            Divider(height: 20),
            Text(
              'Lat: ${col.locationLat!.toStringAsFixed(6)}, Lng: ${col.locationLng!.toStringAsFixed(6)}',
              style: TextStyle(fontSize: 12, color: context.cTextSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// Paalala na tapos na ang koleksyon — walang kailangang gawin.
  Widget _completedNoteBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.riderGreen.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.riderGreen, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This collection is completed. No further action is required.',
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.riderGreen,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeclinedBody(CollectionAssignmentModel col) {
    final schedule = col.loanSchedule;
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Icon(Icons.block_outlined, size: 42, color: AppColors.error),
                SizedBox(height: 10),
                Text('Collection Declined',
                    style: TextStyle(
                        color: AppColors.error,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text('You declined this assignment.',
                    style:
                        TextStyle(color: context.cTextSecondary, fontSize: 12)),
              ],
            ),
          ),
          SizedBox(height: 14),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: context.cBorder)),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Details',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Divider(height: 20),
                  _InfoTile('Lender',
                      col.lenderName.isEmpty ? 'N/A' : col.lenderName),
                  _InfoTile('Loan #',
                      col.loanNumber.isEmpty ? 'N/A' : col.loanNumber),
                  _InfoTile('Due Date', schedule?['due_date'] ?? 'N/A'),
                  _InfoTile('Status', col.statusLabel),
                  if (col.notes != null && col.notes!.isNotEmpty)
                    _InfoTile('Assigned Notes', col.notes!),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Details Tab ──────────────────────────────────────────────────────────
  /// Step 1 — Details + Collect (pinagsama). Ang dating Step 2 (Collect) ay
  /// nasa ibaba na nito, kaya 3 steps na lang: Details → Proof → Review.
  Widget _buildDetailsTab(CollectionAssignmentModel col) {
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    // Ang Collect section ay lumalabas lang kapag na-accept na ang assignment
    // (nasa ibaba ang Accept / Decline).
    final showCollect = col.status == 'accepted' || col.status == 'in_progress';

    if (!isDesktop) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._detailsCards(col),
            if (showCollect) ..._collectCards(col),
          ],
        ),
      );
    }

    // DESKTOP: dalawang column — read-only na impormasyon sa KALIWA, ang
    // form/actions sa KANAN. Dati, isang column lang na nakaunat sa buong
    // lapad: kalahati ng bawat card ay blangko at mahirap sundan ang
    // label → value.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: showCollect
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _detailsCards(col),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _collectCards(col),
                      ),
                    ),
                  ],
                )
              // Wala pang collect form (hindi pa accepted) — huwag hayaang
              // humaba nang buong lapad ang mga info card.
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _detailsCards(col),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// Desktop: naka-cap (1240) at nakasentro ang content ng isang tab —
  /// kapareho ng completed receipt at ng ibang rider desktop pages. Sa mobile,
  /// ibinabalik lang ang orihinal na widget (walang binago).
  Widget _desktopCap(Widget child) {
    if (MediaQuery.sizeOf(context).width < kDesktopBreakpoint) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: child,
      ),
    );
  }

  /// Step 1 (Details) cards — Lender Information MUNA, tapos ang Collection.
  List<Widget> _detailsCards(CollectionAssignmentModel col) {
    return [
      ..._lenderInfoCards(col),
      ..._summaryCards(col),
    ];
  }

  /// Amount/date summary card (dating "Collection Summary").
  List<Widget> _summaryCards(CollectionAssignmentModel col) {
    final schedule = col.loanSchedule;
    final amountDue = (schedule?['amount_due'] as num?)?.toDouble() ?? 0;
    return [
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.cBorder)),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.riderGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.receipt_long_outlined,
                        color: AppColors.riderGreen, size: 18),
                  ),
                  SizedBox(width: 10),
                  Text('Collection',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
              SizedBox(height: 16),
              // Label sa kaliwa, halaga sa kanan — naka-align sa mga
              // _InfoTile sa ibaba, at hindi na button-like na green box.
              // Ang halagang HININGI ng lender ang ipinapakita (hindi ang
              // naka-default na installment amount). Hal. ₱200 ang due pero
              // ₱5,000 ang hininging kolektahin — ₱5,000 ito.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 140,
                      child: Text('Amount to Collect',
                          style: TextStyle(
                              fontSize: 12, color: context.cTextSecondary))),
                  Expanded(
                      child: Text(col.expectedAmount.toCurrency,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: context.cTextPrimary))),
                ],
              ),
              SizedBox(height: 16),
              _InfoTile('Due Date', schedule?['due_date'] ?? 'N/A'),
              // Kapag iba ang hiningi sa installment due, ipakita rin ito para
              // malinaw kung saan galing ang halaga (partial o advance).
              if ((col.expectedAmount - amountDue).abs() > 0.005)
                _InfoTile('Installment Due', amountDue.toCurrency),
              _InfoTile('Period',
                  'Period ${schedule?['period_number'] ?? schedule?['installment_number'] ?? ''}'),
              _InfoTile('Status', col.statusLabel),
              if (col.amountCollected != null)
                _InfoTile('Collected', col.amountCollected!.toCurrency),
              if (col.completedAt != null)
                _InfoTile('Completed At',
                    DateFormat('MMM d, yyyy h:mm a').format(col.completedAt!)),
              if (col.collectionSchedule != null)
                _InfoTile(
                    'Scheduled',
                    DateFormat('MMM d, yyyy h:mm a')
                        .format(col.collectionSchedule!)),
              if (col.notes != null && col.notes!.isNotEmpty)
                _InfoTile('Assigned Notes', col.notes!),
            ],
          ),
        ),
      ),
      SizedBox(height: 12),
    ];
  }

  /// Lender Information card. (Ang Accept/Decline ay naka-pin na sa baba ng
  /// screen — tingnan ang `_buildAcceptDeclineBar`.)
  List<Widget> _lenderInfoCards(CollectionAssignmentModel col) {
    return [
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.cBorder)),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // `cBrandGreen` para manatiling visible sa dark mode.
                  Icon(Icons.person_outline,
                      color: context.cBrandGreen, size: 18),
                  SizedBox(width: 8),
                  Text('Lender Information',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
              SizedBox(height: 14),
              _InfoTile(
                  'Name', col.lenderName.isEmpty ? 'N/A' : col.lenderName),
              _InfoTile(
                  'Loan #', col.loanNumber.isEmpty ? 'N/A' : col.loanNumber),
              _InfoTile(
                  'Phone',
                  (col.loanSchedule?['loan']?['lender_profiles']?['users']
                          ?['phone_number'] as String?) ??
                      (col.lenderPhone.isEmpty ? 'N/A' : col.lenderPhone)),
              if (col.lenderAddresses.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                        width: 140,
                        child: Text('Address',
                            style: TextStyle(
                                fontSize: 12, color: context.cTextSecondary))),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: col.lenderAddresses.take(2).map((a) {
                          final m = a as Map<String, dynamic>;
                          final full = [
                            m['street'],
                            m['barangay'],
                            m['city'],
                            m['province']
                          ]
                              .where(
                                  (e) => e != null && (e as String).isNotEmpty)
                              .join(', ');
                          // Address value sa KANAN ng label — pareho ng
                          // alignment ng ibang info rows (walang chip).
                          return Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Text(full.isEmpty ? 'N/A' : full,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: context.cTextPrimary)),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      SizedBox(height: 8),
    ];
  }

  /// Accept / Decline action bar — naka-pin sa BABA ng mobile view (hindi na
  /// kailangang mag-scroll) kapag 'assigned' pa ang collection.
  Widget _buildAcceptDeclineBar(CollectionAssignmentModel col) {
    final busy = ref.read(riderCollectionProvider).isSubmitting;
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: context.cSurface,
        border: Border(top: BorderSide(color: context.cBorder)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      // Desktop: hindi nakaunat sa buong lapad ang dalawang button — naka-cap
      // at nakasentro, kapareho ng content sa itaas.
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 1240 : 1200),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final ok = await ref
                                .read(riderCollectionProvider.notifier)
                                .decline(widget.collectionId);
                            if (mounted && ok) context.pop();
                          },
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error),
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text('Decline'),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    // Walang lilipatang step — nasa Step 1 na ang Details at
                    // Collect; ang provider reload ang magpapakita ng fields.
                    onPressed: busy
                        ? null
                        : () => ref
                            .read(riderCollectionProvider.notifier)
                            .accept(widget.collectionId),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.riderGreen,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.riderGreen.withValues(alpha: 0.6),
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Accept'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Dating Step 2 (Collect) content — ngayon ay nasa loob na ng Step 1.
  /// Listahan ito ng widgets para direkta nang isingit sa `_buildDetailsTab`.
  List<Widget> _collectCards(CollectionAssignmentModel col) {
    final alreadyRecorded = col.amountCollected != null;
    final hasAmount = _amountCtrl.text.isNotEmpty;

    return [
      if (alreadyRecorded) ...[
        SizedBox(height: 12),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.successLight,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.riderGreen.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.riderGreen, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Already recorded: ${col.amountCollected!.toCurrency} — you can edit or continue.',
                    style:
                        TextStyle(fontSize: 13, color: AppColors.riderGreen)),
              ),
            ],
          ),
        ),
      ],
      SizedBox(height: 18),
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.cBorder)),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Collection Details',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.cTextPrimary)),
              SizedBox(height: 14),
              // Sariling label sa itaas ng field — hindi na kailangang
              // lumipad ng label ng field, na napuputol kapag madilim ang
              // likod (wala sa loob ng puting fill ang kalahati nito).
              Text(
                  alreadyRecorded
                      ? 'Amount Collected (₱) — recorded'
                      : 'Amount Collected (₱) *',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.cTextSecondary)),
              SizedBox(height: 6),
              AppTextField(
                  controller: _amountCtrl,
                  label: 'Amount Collected',
                  hint: '0.00',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  // Comma separator habang nagta-type: 32000 -> 32,000.
                  inputFormatters: const [ThousandsSeparatorInputFormatter()],
                  prefixIcon: Icons.payments_outlined,
                  enabled: !alreadyRecorded),
              SizedBox(height: 14),
              Text('Rider Notes (optional)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.cTextSecondary)),
              SizedBox(height: 6),
              AppTextField(
                  controller: _notesCtrl,
                  label: 'Rider Notes',
                  hint: 'Your own note about this collection...',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  maxLines: 3,
                  prefixIcon: Icons.sticky_note_2_outlined),
            ],
          ),
        ),
      ),
      SizedBox(height: 16),
      // Back + Next — nasa ilalim ng Collection Details card.
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              // Na-merge na ang Collect sa Step 1, kaya walang dating step
              // na babalikan — binabalik na lang nito ang rider sa listahan.
              onPressed: () => context.pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.cTextSecondary,
                side: BorderSide(color: context.cBorder),
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Back'),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            // Pantay ang lapad ng Back at Next.
            child: ElevatedButton(
              // Next = validation lang papuntang Proof (walang record sa
              // server hangga't hindi pa ni-submit sa Step 3).
              onPressed: alreadyRecorded
                  ? () => _goToStep(1)
                  : (!hasAmount || _isSubmitting)
                      ? null
                      : _validateAmountAndNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.riderGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Next',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
            ),
          ),
        ],
      ),
      SizedBox(height: 8),
    ];
  }

  Widget _buildProofTab(CollectionAssignmentModel col) {
    if (col.status == 'completed') {
      return SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.riderGreen, AppColors.riderGreenDark]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.verified_outlined, size: 40, color: Colors.white),
                  SizedBox(height: 10),
                  Text('Collection completed!',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(
                    'Amount: ${col.amountCollected?.toCurrency ?? '—'}',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  if (col.completedAt != null)
                    Text(
                      'Completed: ${DateFormat('MMM d, yyyy h:mm a').format(col.completedAt!)}',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),
            SizedBox(height: 16),
            AppButton(
              label: 'Go to Review',
              onPressed: () => _goToStep(2),
              color: AppColors.riderGreen,
              icon: Icons.arrow_forward,
            ),
          ],
        ),
      );
    }

    final needCollectFirst = col.status == 'assigned' ||
        (col.status == 'accepted' &&
            col.amountCollected == null &&
            _amountCtrl.text.isEmpty);

    // Parehong widgets sa mobile at desktop — ang layout lang ang nag-iiba.
    final warning = _proofLockBanner();
    final paymentCard = _paymentProofCard();
    final signatureCard = _signatureCard();
    final navActions = _proofNavActions(col);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    if (!isDesktop) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (needCollectFirst) warning,
            if (!needCollectFirst) ...[
              paymentCard,
              SizedBox(height: 14),
              signatureCard,
              SizedBox(height: 16),
              navActions,
            ],
            SizedBox(height: 16),
          ],
        ),
      );
    }

    // DESKTOP: DALAWANG COLUMN — Payment Proof sa KALIWA, Lender Signature sa
    // KANAN — at naka-cap (1080) ang buong hakbang. Dati, isang column lang na
    // nakaunat sa buong lapad: blangko ang kalahati ng bawat card at sobrang
    // lapad ng signature canvas, kaya mukhang mobile page na pinahaba.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (needCollectFirst) warning,
              if (!needCollectFirst) ...[
                // PANTATAG na taas: ang Payment Proof card ang umabot sa
                // aktwal na taas ng Lender Signature card (hindi na mas
                // maikli/mabitin ang isa). IntrinsicHeight ang kailangan para
                // mag-stretch sa loob ng scroll view, kung saan unbounded ang
                // taas ng Row.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [paymentCard],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(flex: 6, child: signatureCard),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Back + Next sa ibaba, naka-align sa KANAN — hindi nakaunat
                // sa buong lapad.
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: navActions,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Yellow lock banner kapag hindi pa naka-record ang amount (kailangan munang
  /// pumunta sa Collect step bago mag-upload ng proof).
  Widget _proofLockBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.warning.withValues(alpha: 0.3))),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: AppColors.warning, size: 18),
          SizedBox(width: 10),
          Expanded(
              child: Text(
                  'Record the collected amount in Collect step first before uploading proof.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                      height: 1.3))),
          SizedBox(width: 8),
          TextButton(
            onPressed: () => _goToStep(0),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.warning,
              padding: EdgeInsets.symmetric(horizontal: 8),
            ),
            child:
                Text('Go to Collect', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Inline na error/size caption sa ilalim ng Payment Proof card — isang
  /// caption lang para sa BUONG upload (1–2 photos), kaya makikita agad kung
  /// pasok pa sa 5MB ang suma.
  List<Widget> _proofValidationNotice() {
    if (_proofError != null) {
      return [
        SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.errorLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 16, color: AppColors.error),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  _proofError!,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    if (_proofPhotos.isEmpty) {
      return [
        SizedBox(height: 8),
        Text(
          'Upload 1 or 2 photos — max ${CiEvidenceRules.maxLabel} in total.',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.cTextTertiary),
        ),
      ];
    }
    return [
      SizedBox(height: 8),
      // "Upload size" — aktwal na ipapadala pagkatapos i-resize/i-compress ng
      // picker, hindi ang laki ng orihinal na file.
      Text(
        'Upload size: ${CiEvidenceRules.sizeLabel(_proofTotalBytes)} of '
        '${CiEvidenceRules.maxLabel} · ${_proofPhotos.length}/2 photos',
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.cTextTertiary),
      ),
    ];
  }

  /// Card ng Payment Proof — ISA o DALAWA na photo sa iisang card. Hindi per
  /// photo ang limit: ang KABUUANG laki ng 1–2 photos ang dapat ≤ 5MB. Ang
  /// unang photo ang `proof_photo`, ang pangalawa (kung meron) ang
  /// `scene_photo` sa backend.
  Widget _paymentProofCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Theme-aware fill — kapag `Colors.white` ito, puti ang card
        // sa dark mode at puti/light din ang text (hindi visible).
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
              Icon(Icons.receipt_long_outlined,
                  color: AppColors.riderGreen, size: 18),
              SizedBox(width: 8),
              Text('Payment Proof',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.cTextPrimary)),
              const Spacer(),
              // Bilang ng napiling photo (max 2) — malinaw kung ilan pa ang
              // puwedeng idagdag.
              Text('${_proofPhotos.length}/2',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.cTextTertiary)),
            ],
          ),
          SizedBox(height: 12),
          _proofPhotosStrip(),
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              // Naka-disable kapag kumpleto na ang 2 photos — i-remove muna ang
              // isa para makapagpalit.
              onPressed:
                  _proofPhotos.length >= 2 ? null : _showProofSourceSheet,
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: const Text('Upload',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.cBrandGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: context.cBorder,
                disabledForegroundColor: context.cTextTertiary,
                elevation: 0,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          // Inline validation + size caption para sa BUONG upload
          // (kapareho ng CI Task, pero total ang sinusukat).
          ..._proofValidationNotice(),
        ],
      ),
    );
  }

  /// ISANG design lang: iisang preview area sa card. Dito lumalabas ang mga
  /// napiling photo (isa o dalawa) at ang "Add photo" tile — hindi dalawang
  /// blangkong kahon agad. Kapag wala pa, isa lang ang blangkong tile.
  Widget _proofPhotosStrip() {
    final tiles = <Widget>[
      for (var i = 0; i < _proofPhotos.length; i++) _proofPhotoTile(i),
      if (_proofPhotos.length < 2) _proofAddTile(),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }

  /// Napiling photo — pindutin para i-view; may ✕ sa sulok para i-remove.
  Widget _proofPhotoTile(int index) {
    final photo = _proofPhotos[index];
    return GestureDetector(
      onTap: () => _viewProofPhoto(index),
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            XFilePreview(file: photo, height: 160, width: double.infinity),
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => _removeProofPhoto(index),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle),
                  child:
                      const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ang nag-iisang blangkong design — pinipindot para magdagdag ng photo.
  /// Buong lapad kapag wala pa; kalahati na lang kapag may isa nang photo.
  Widget _proofAddTile() {
    final isEmpty = _proofPhotos.isEmpty;
    return GestureDetector(
      onTap: _showProofSourceSheet,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_photo_alternate_outlined,
                  size: 26, color: AppColors.textTertiary),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  isEmpty ? 'No photo uploaded yet' : 'Add second photo',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Card ng Lender Signature (optional) — signature pad lang.
  Widget _signatureCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Theme-aware fill — kapag `Colors.white` ito, puti ang card
        // sa dark mode at puti/light din ang text (hindi visible).
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
              Icon(Icons.draw_outlined,
                  color: AppColors.riderGreen, size: 18),
              SizedBox(width: 8),
              // Flexible — para hindi umapaw ang mahabang title sa maliit na
              // screen o kapag malaki ang text scale.
              Flexible(
                child: Text('Lender Signature (optional)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.cTextPrimary)),
              ),
            ],
          ),
          SizedBox(height: 12),
          SignaturePad(
            // Mas mataas na canvas para sa lender signature card.
            height: 300,
            // Text-only ang Clear / Confirm — walang ✕ at ✓ icons.
            showActionIcons: false,
            // "Signature cleared" feedback: 1 segundo lang (rider flow).
            clearedFeedbackDuration: const Duration(seconds: 1),
            onSignatureChanged: (base64) =>
                setState(() => _signatureBase64 = base64),
          ),
          // Plain status text lang — hindi pill/button ang itsura.
          if (_signatureBase64 != null)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, color: context.cBrandGreen, size: 14),
                  SizedBox(width: 6),
                  Text('Signature captured',
                      style: TextStyle(
                          fontSize: 12,
                          color: context.cTextSecondary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Back + Next — nasa ibaba ng Lender Signature card sa mobile at naka-align
  /// sa kanan sa desktop. Parehong lapad ang dalawang button.
  Widget _proofNavActions(CollectionAssignmentModel col) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _goToStep(0),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.cTextSecondary,
              side: BorderSide(color: context.cBorder),
              minimumSize: const Size(0, 46),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Back'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            // Kailangan muna ng payment proof bago makalipat sa Step 3.
            onPressed: _proofPhotos.isNotEmpty
                ? () => _validateProofAndNext(col)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.riderGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Next', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Step 3 (Review) — scrollable ang Review Summary card, at ang Back +
  /// Submit ay naka-pin sa ibaba ng mobile view (plain buttons, hindi footer na
  /// may background/border).
  Widget _buildReviewTab(CollectionAssignmentModel col) {
    final navActions = _reviewNavActions(col);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    if (!isDesktop) {
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: _reviewSummaryCard(col),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: navActions,
          ),
        ],
      );
    }

    // DESKTOP: DALAWANG column — Lendee & Loan info sa KALIWA, ang collection
    // amounts / proof checks sa KANAN — at naka-cap (1080) at nakasentro ang
    // buong hakbang. Dati, isang card lang na nakaunat sa buong lapad: blangko
    // ang kanang kalahati ng bawat row at mahirap sundan ang label → value.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _reviewCard(
                      icon: Icons.person_outline,
                      title: 'Lendee & Loan',
                      rows: _reviewLenderRows(col),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _reviewCard(
                      icon: Icons.summarize_outlined,
                      title: 'Collection Details',
                      rows: _reviewCollectionRows(col),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Back + Submit sa ibaba, naka-align sa KANAN — hindi nakaunat
              // sa buong lapad.
              Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: navActions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Back + Submit (pareho sa mobile at desktop, layout lang ang nag-iiba).
  Widget _reviewNavActions(CollectionAssignmentModel col) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _goToStep(1),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.cTextSecondary,
              side: BorderSide(color: context.cBorder),
              minimumSize: const Size(0, 46),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Back'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : () => _submitReview(col),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.riderGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Submit',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  /// Review card na may header + listahan ng rows (desktop two-column view).
  Widget _reviewCard({
    required IconData icon,
    required String title,
    required List<Widget> rows,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Theme-aware fill — dating `Colors.white` (puti-sa-puti sa
        // dark mode, kaya hindi visible ang mga label).
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
              Icon(icon, color: AppColors.riderGreen, size: 18),
              SizedBox(width: 8),
              Flexible(
                child: Text(title,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          Divider(height: 20),
          ...rows,
        ],
      ),
    );
  }

  /// Lender + loan info rows — kaliwang column sa desktop, unang kalahati ng
  /// summary card sa mobile.
  List<Widget> _reviewLenderRows(CollectionAssignmentModel col) {
    final schedule = col.loanSchedule;
    final amountDue = (schedule?['amount_due'] as num?)?.toDouble() ?? 0;
    return [
      _ReviewRow('Lender', col.lenderName.isEmpty ? '—' : col.lenderName),
      _ReviewRow('Loan #', col.loanNumber.isEmpty ? '—' : col.loanNumber),
      _ReviewRow('Due Date', schedule?['due_date'] ?? '—'),
      _ReviewRow('Amount to Collect', col.expectedAmount.toCurrency,
          valueColor: context.cTextPrimary, valueBold: true),
      // Kapag iba ang hiningi sa installment due, ipakita rin ito para malinaw
      // kung partial/advance ang hininging bayad.
      if ((col.expectedAmount - amountDue).abs() > 0.005)
        _ReviewRow('Installment Due', amountDue.toCurrency),
    ];
  }

  /// Collection amounts, proof/signature checks, at status rows — kanang column
  /// sa desktop, ikalawang kalahati ng summary card sa mobile.
  List<Widget> _reviewCollectionRows(CollectionAssignmentModel col) {
    final collectedStr = col.amountCollected?.toCurrency ??
        (_amountCtrl.text.isEmpty ? '—' : '₱${_amountCtrl.text}');
    final riderNotes = _notesCtrl.text.trim();
    return [
      // Plain row na lang — hindi na green box/button ang itsura.
      _ReviewRow('Amount Collected', collectedStr, valueBold: true),
      // Proof at Lender Signature — check kapag meron, `N/A` kapag wala. Ang
      // proof ay 1–2 photos sa iisang card, kaya bilang ang label.
      _ReviewCheckRow('Proof',
          present: _proofPhotos.isNotEmpty,
          presentLabel: _proofPhotos.length > 1 ? '2 photos' : '1 photo'),
      _ReviewCheckRow('Lender Signature',
          present: _signatureBase64 != null, presentLabel: 'Captured'),
      // Hiwalay ang na-assign na notes (read-only, galing sa staff) sa sariling
      // note ng rider — hindi na nito ginagamit ang `col.notes` bilang rider
      // note kaya hindi ito maipapasa/papalitan ng rider.
      if (col.notes != null && col.notes!.trim().isNotEmpty)
        _ReviewRow('Assigned Notes', col.notes!.trim()),
      if (riderNotes.isNotEmpty) _ReviewRow('Rider Notes', riderNotes),
      _ReviewRow('Status', col.statusLabel),
      // Business rule: ang `completed_at` ay may halaga lang kapag tapos na
      // talaga ang koleksyon (status = 'completed'). Hindi na ito sine-set ng
      // record step, kaya hindi na lumalabas ang mapanlinlang na "Completed"
      // na timestamp habang in_progress.
      if (col.status == 'completed' && col.completedAt != null)
        _ReviewRow('Completed',
            DateFormat('MMM d, yyyy h:mm a').format(col.completedAt!)),
    ];
  }

  /// Review Summary card (mobile) — Lender info, amounts, at proof/signature
  /// checks sa isang card.
  Widget _reviewSummaryCard(CollectionAssignmentModel col) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _reviewCard(
        icon: Icons.summarize_outlined,
        title: 'Review Details',
        rows: [
          ..._reviewLenderRows(col),
          ..._reviewCollectionRows(col),
        ],
      ),
    ]);
  }
}


// ── helpers ────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mas maluwag na label column (dati 110) — hindi na dumidikit ang
          // value sa mahabang label gaya ng "Amount to Collect".
          SizedBox(
              width: 140,
              child: Text(label,
                  style:
                      TextStyle(fontSize: 12, color: context.cTextSecondary))),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.cTextPrimary))),
        ],
      ),
    );
  }
}

/// Review row para sa proof / signature — green check kapag meron, `N/A` kapag
/// wala (hal. optional na lender signature).
class _ReviewCheckRow extends StatelessWidget {
  final String label;
  final bool present;

  /// Text sa tabi ng check kapag meron ang proof/signature.
  final String presentLabel;
  const _ReviewCheckRow(this.label,
      {required this.present, this.presentLabel = 'Attached'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
              width: 145,
              child: Text(label,
                  style:
                      TextStyle(fontSize: 14, color: context.cTextSecondary))),
          Expanded(
            child: present
                ? Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: context.cBrandGreen, size: 18),
                      SizedBox(width: 6),
                      Text(presentLabel,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.cTextPrimary)),
                    ],
                  )
                : Text('N/A',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.cTextTertiary)),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;
  const _ReviewRow(this.label, this.value,
      {this.valueColor, this.valueBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 145,
              child: Text(label,
                  style:
                      TextStyle(fontSize: 14, color: context.cTextSecondary))),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: valueBold ? FontWeight.w800 : FontWeight.w600,
                    color: valueColor ?? context.cTextPrimary)),
          ),
        ],
      ),
    );
  }
}

