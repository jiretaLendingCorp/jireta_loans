// ignore_for_file: unused_element, prefer_const_constructors, prefer_const_literals_to_create_immutables
// lib/presentation/features/rider/collections/screens/rider_collection_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
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
import '../../../../shared/widgets/signature_pad.dart';
import '../../../../shared/widgets/document_viewer.dart';
import '../providers/rider_collection_provider.dart';
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
  XFile? _proofPhoto;
  XFile? _scenePhoto;
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

  Future<void> _pickImage(bool isProof) async {
    final picked = await _imagePicker.pickImage(
        source: ImageSource.camera, imageQuality: 80, maxWidth: 1920);
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

  Future<void> _pickImageGallery(bool isProof) async {
    final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1920);
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

  Future<void> _recordAndNext(CollectionAssignmentModel col) async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      context.showSnackBarAsToast(
          const SnackBar(content: Text('Please enter a valid amount')));
      return;
    }

    // Confirm
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Confirm Collection',
        message: 'Record ${amount.toCurrency} as collected from lender?',
        confirmText: 'Record & Continue',
        confirmColor: AppColors.riderGreen,
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      final ok =
          await ref.read(riderCollectionProvider.notifier).recordCollection(
                assignmentId: widget.collectionId,
                amountCollected: amount,
                notes: _notesCtrl.text.trim().isEmpty
                    ? null
                    : _notesCtrl.text.trim(),
              );
      if (mounted) {
        if (ok) {
          // Success — auto next to Proof (Step 2 na ngayon)
          _goToStep(1);
          context.showSnackBarAsToast(
            const SnackBar(
              content: Text('Amount recorded — upload proof next'),
              backgroundColor: AppColors.riderGreen,
            ),
          );
        } else {
          final errMsg =
              ref.read(riderCollectionProvider).error ?? 'Failed to record collection';
          showDialog(
              context: context, builder: (_) => ErrorDialog(message: errMsg));
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _validateProofAndNext(CollectionAssignmentModel col) {
    if (_proofPhoto == null && col.status != 'completed') {
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

    if (_proofPhoto == null) {
      context.showSnackBarAsToast(
          const SnackBar(content: Text('Please add payment proof in Proof step')));
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
            'Submit $amountText with proof? This will complete the collection.',
        confirmText: 'Submit',
        confirmColor: AppColors.riderGreen,
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      // Refresh first: the cached `col` may be stale (e.g. record succeeded
      // in Collect step but this Review tab still sees amountCollected==null).
      // Without this, a retry would call `record` again on an `in_progress`
      // assignment, backend returns 400, and proof upload never runs —
      // stuck sa "in progress" forever.
      var fresh = col;
      try {
        await ref
            .read(riderCollectionProvider.notifier)
            .loadDetails(widget.collectionId, silent: true);
        final updated =
            ref.read(riderCollectionProvider).selectedCollection;
        if (updated != null) fresh = updated;
      } catch (_) {}
      final freshHasAmount = fresh.amountCollected != null ||
          fresh.status == 'in_progress' ||
          fresh.status == 'completed';

      // If still need to record amount, do it first
      if (!freshHasAmount && pendingAmount != null) {
        final okRecord = await ref
            .read(riderCollectionProvider.notifier)
            .recordCollection(
              assignmentId: widget.collectionId,
              amountCollected: pendingAmount,
              notes: _notesCtrl.text.trim().isEmpty
                  ? null
                  : _notesCtrl.text.trim(),
            );
        if (!okRecord) {
          // Recovery: baka na-record na pala sa backend (race/stale cache)
          // — reload at kung may amount na, tumuloy sa proof upload imbes
          // na mag-abort.
          try {
            await ref
                .read(riderCollectionProvider.notifier)
                .loadDetails(widget.collectionId, silent: true);
            final retry =
                ref.read(riderCollectionProvider).selectedCollection;
            final recovered = retry != null &&
                (retry.amountCollected != null ||
                    retry.status == 'in_progress' ||
                    retry.status == 'completed');
            if (!recovered) {
              if (mounted) {
                final errMsg = ref
                        .read(riderCollectionProvider)
                        .error ??
                    'Failed to record amount';
                showDialog(
                    context: context, builder: (_) => ErrorDialog(message: errMsg));
              }
              return;
            }
          } catch (_) {
            if (mounted) {
              showDialog(
                  context: context,
                  builder: (_) =>
                      const ErrorDialog(message: 'Failed to record amount'));
            }
            return;
          }
        }
      }

      // Now upload proof
      final okProof = await ref
          .read(riderCollectionProvider.notifier)
          .uploadProof(
            assignmentId: widget.collectionId,
            proofPhoto: _proofPhoto!,
            scenePhoto: _scenePhoto,
            signatureBase64: _signatureBase64,
          );

      if (mounted) {
        if (okProof) {
          await showDialog(
            context: context,
            builder: (_) => const SuccessDialog(
                message: 'Proof uploaded and collection completed!'),
          );
          if (mounted) context.pop();
        } else {
          final errMsg = ref.read(riderCollectionProvider).error ??
              'Failed to upload proof. Naka-record na ang cash (in_progress) — subukan ulit mag-upload ng proof para maging completed.';
          showDialog(
              context: context, builder: (_) => ErrorDialog(message: errMsg));
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// True kapag may dapat i-render na primary action sa bottom bar. Walang
  /// bottom bar sa Details step — ang Accept / Decline at ang "Next" button ay
  /// nasa loob ng tab mismo.
  bool _hasPrimaryAction(CollectionAssignmentModel col) {
    if (col.status == 'completed') return true; // "Done"
    // Details at Collect steps: ang mga button (Accept/Decline, Back, Next) ay
    // nasa loob na ng tab — walang bottom bar.
    return _tabController.index >= 2;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCollectionProvider);
    final col = state.selectedCollection;

    // Sync amount/notes if loaded and controllers empty
    if (col != null) {
      if (_amountCtrl.text.isEmpty && col.amountCollected != null) {
        _amountCtrl.text =
            ThousandsSeparatorInputFormatter.format(col.amountCollected!);
      }
      if (_notesCtrl.text.isEmpty && col.notes != null) {
        _notesCtrl.text = col.notes!;
      }
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
                      style: TextStyle(fontSize: 12, color: context.cTextSecondary)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.read(riderCollectionProvider.notifier).loadDetails(widget.collectionId),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.riderGreen),
                    child: Text('Retry', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
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
              if (col != null && !_isReadOnlyStatus(col.status))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Step ${_tabController.index + 1} of ${_steps.length}: ${_steps[_tabController.index]}',
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
                          // Green AppBar: keep the status readable.
                          onDark: true))),
          ],
        ),
        body: state.isLoading || !_detailsResolved
            ? const ShimmerLoader()
            : col == null
                ? Center(child: Text('Collection not found'))
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
                                  _buildProofTab(col),
                                  _buildReviewTab(col),
                                ],
                              ),
                            ),
                            _buildBottomNav(col),
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
                                Icon(Icons.bug_report, color: AppColors.error, size: 36),
                                SizedBox(height: 8),
                                Text('Build error: $e',
                                    style: TextStyle(color: AppColors.error, fontSize: 12)),
                                SizedBox(height: 8),
                                Text(st.toString(),
                                    style: TextStyle(fontSize: 10, color: context.cTextTertiary)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  },
                ),
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
                  Text('Outer build error: $e', style: TextStyle(color: AppColors.error, fontSize: 12)),
                  SizedBox(height: 8),
                  Text(st.toString(), style: TextStyle(fontSize: 10, color: context.cTextTertiary)),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  /// Completed / declined / failed collections are read-only receipts — walang
  /// 4-step wizard, kaya walang step label sa header.
  bool _isReadOnlyStatus(String status) =>
      status == 'completed' || status == 'declined' || status == 'failed';

  Widget _buildBottomNav(CollectionAssignmentModel col) {
    final idx = _tabController.index;
    final isFirst = idx == 0;
    final isLast = idx == _steps.length - 1;
    final isCompleted = col.status == 'completed';

    // Walang bottom button kapag walang primary action (hal. status = 'assigned'
    // sa Details step) — hindi na dapat lumabas ang bar na may "Accept to
    // continue" row na walang laman.
    if (!_hasPrimaryAction(col)) return const SizedBox.shrink();

    // Hide bottom nav for completed? Keep but show Done.
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: context.cSurface,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          if (!isFirst)
            Expanded(
              child: OutlinedButton(
                onPressed: () => _goToStep(idx - 1),
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
          if (!isFirst) SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _buildPrimaryAction(col, idx, isLast, isCompleted),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction(
      CollectionAssignmentModel col, int idx, bool isLast, bool isCompleted) {
    if (isCompleted) {
      return ElevatedButton(
        onPressed: () => context.pop(),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.riderGreen,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text('Done',
            style: TextStyle(fontWeight: FontWeight.w700)),
      );
    }

    // Step-specific primary
    switch (idx) {
      case 0: // Details + Collect
        // Lahat ng button (Accept / Decline / Back / Next) ay nasa loob na ng
        // Step 1 — walang bottom bar.
        return const SizedBox.shrink();
      case 1: // Proof
        final hasProof = _proofPhoto != null;
        return ElevatedButton(
          onPressed: hasProof ? () => _validateProofAndNext(col) : null,
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
              Text('Continue to Review',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        );
      case 2: // Review
        return ElevatedButton(
          onPressed: _isSubmitting ? null : () => _submitReview(col),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.riderGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    Icon(Icons.cloud_upload_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Submit Collection',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Read-only footer for completed/declined ───────────────────────────────
  Widget _buildReadOnlyFooter(CollectionAssignmentModel col) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: context.cSurface,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: col.status == 'completed'
                ? AppColors.riderGreen
                : context.cTextSecondary,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            col.status == 'completed' ? 'Done' : 'Back to Collections',
            style: TextStyle(fontWeight: FontWeight.w700),
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
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Success banner
          Container(
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
                Text(
                  col.amountCollected != null
                      ? col.amountCollected!.toCurrency
                      : '₱0.00',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 4),
                Text(
                  'Amount collected from lender',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12),
                ),
                if (col.completedAt != null) ...[
                  SizedBox(height: 8),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      DateFormat('MMM d, yyyy  •  h:mm a')
                          .format(col.completedAt!),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 14),
          // Lender info card
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
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  SizedBox(height: 14),
                  _InfoTile('Name',
                      col.lenderName.isEmpty ? 'N/A' : col.lenderName),
                  _InfoTile('Loan #',
                      col.loanNumber.isEmpty ? 'N/A' : col.loanNumber),
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
                            width: 110,
                            child: Text('Address',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.cTextSecondary))),
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
                              ].where((e) => e != null && (e as String).isNotEmpty).join(', ');
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
          SizedBox(height: 12),
          // Collection card - dating "Collection Summary"; nasa ibaba na ng
          // Lender Information gaya ng wizard Details tab.
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
                      Icon(Icons.receipt_long_outlined,
                          color: AppColors.riderGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Collection',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Divider(height: 20),
                  _InfoTile('Due Date', schedule?['due_date'] ?? 'N/A'),
                  _InfoTile('Period',
                      'Period ${schedule?['period_number'] ?? schedule?['installment_number'] ?? '—'}'),
                  _InfoTile('Amount Due', amountDue.toCurrency),
                  _InfoTile('Amount Collected',
                      col.amountCollected?.toCurrency ?? '—'),
                  _InfoTile('Status', col.statusLabel),
                  if (col.completedAt != null)
                    _InfoTile(
                        'Completed',
                        DateFormat('MMM d, yyyy h:mm a')
                            .format(col.completedAt!)),
                  if (col.collectionSchedule != null)
                    _InfoTile(
                        'Scheduled',
                        DateFormat('MMM d, yyyy h:mm a')
                            .format(col.collectionSchedule!)),
                  if (col.notes != null && col.notes!.isNotEmpty)
                    _InfoTile('Notes', col.notes!),
                  if (col.idempotencyKey != null)
                    _InfoTile('Ref', col.idempotencyKey!),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          // Proof viewer - read only, show stored URLs
          if (col.proofPhoto != null ||
              col.collectionPhoto != null ||
              col.borrowerSignature != null)
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
                        Icon(Icons.photo_library_outlined,
                            color: AppColors.riderGreen, size: 18),
                        SizedBox(width: 8),
                        Text('Collection Proof',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text('Photos and signature submitted for this collection',
                        style: TextStyle(
                            fontSize: 11, color: context.cTextSecondary)),
                    SizedBox(height: 12),
                    if (col.proofPhoto != null) ...[
                      Text('Payment Proof',
                          style: TextStyle(
                              fontSize: 11,
                              color: context.cTextSecondary,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 6),
                      DocumentViewer(
                          url: col.proofPhoto,
                          label: 'Payment Proof',
                          height: 200,
                          bucket: 'collection-proofs'),
                      SizedBox(height: 14),
                    ],
                    if (col.collectionPhoto != null) ...[
                      Text('Scene Photo',
                          style: TextStyle(
                              fontSize: 11,
                              color: context.cTextSecondary,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 6),
                      DocumentViewer(
                          url: col.collectionPhoto,
                          label: 'Scene Photo',
                          height: 180,
                          bucket: 'collection-proofs'),
                      SizedBox(height: 14),
                    ],
                    if (col.borrowerSignature != null) ...[
                      Text('Lender Signature',
                          style: TextStyle(
                              fontSize: 11,
                              color: context.cTextSecondary,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 6),
                      DocumentViewer(
                          url: col.borrowerSignature,
                          label: 'Signature',
                          height: 140,
                          bucket: 'collection-proofs'),
                    ],
                  ],
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceGray,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.cBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: context.cTextSecondary, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text('No proof photos stored for this collection.',
                          style: TextStyle(
                              fontSize: 12, color: context.cTextSecondary))),
                ],
              ),
            ),
          if (col.locationLat != null && col.locationLng != null) ...[
            SizedBox(height: 12),
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
                        Icon(Icons.location_on_outlined,
                            color: AppColors.riderGreen, size: 18),
                        SizedBox(width: 8),
                        Text('Collection Location',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Divider(height: 20),
                    Text(
                      'Lat: ${col.locationLat!.toStringAsFixed(6)}, Lng: ${col.locationLng!.toStringAsFixed(6)}',
                      style: TextStyle(
                          fontSize: 12, color: context.cTextSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: 20),
          // Receipt decoration
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.riderGreen.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle,
                    color: AppColors.riderGreen, size: 16),
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
          ),
          SizedBox(height: 80),
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
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  Divider(height: 20),
                  _InfoTile('Lender',
                      col.lenderName.isEmpty ? 'N/A' : col.lenderName),
                  _InfoTile('Loan #',
                      col.loanNumber.isEmpty ? 'N/A' : col.loanNumber),
                  _InfoTile('Due Date', schedule?['due_date'] ?? 'N/A'),
                  _InfoTile('Status', col.statusLabel),
                  if (col.notes != null && col.notes!.isNotEmpty)
                    _InfoTile('Notes', col.notes!),
                ],
              ),
            ),
          ),
          SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Details Tab ──────────────────────────────────────────────────────────
  /// Step 1 — Details + Collect (pinagsama). Ang dating Step 2 (Collect) ay
  /// nasa ibaba na nito, kaya 3 steps na lang: Details → Proof → Review.
  Widget _buildDetailsTab(CollectionAssignmentModel col) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._detailsCards(col),
          // Collect section — hindi ito lumalabas hangga't hindi pa
          // na-a-accept ang assignment (nasa itaas ang Accept / Decline).
          if (col.status == 'accepted' || col.status == 'in_progress')
            ..._collectCards(col),
        ],
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
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  SizedBox(height: 16),
                  // Label sa kaliwa, halaga sa kanan — naka-align sa mga
                  // _InfoTile sa ibaba, at hindi na button-like na green box.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 110,
                          child: Text('Amount Due',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.cTextSecondary))),
                      Expanded(
                          child: Text(amountDue.toCurrency,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: context.cTextPrimary))),
                    ],
                  ),
                  SizedBox(height: 16),
                  _InfoTile('Due Date', schedule?['due_date'] ?? 'N/A'),
                  _InfoTile('Period',
                      'Period ${schedule?['period_number'] ?? schedule?['installment_number'] ?? ''}'),
                  _InfoTile('Status', col.statusLabel),
                  if (col.amountCollected != null)
                    _InfoTile('Collected', col.amountCollected!.toCurrency),
                  if (col.completedAt != null)
                    _InfoTile(
                        'Completed At',
                        DateFormat('MMM d, yyyy h:mm a')
                            .format(col.completedAt!)),
                  if (col.collectionSchedule != null)
                    _InfoTile(
                        'Scheduled',
                        DateFormat('MMM d, yyyy h:mm a')
                            .format(col.collectionSchedule!)),
                  if (col.notes != null && col.notes!.isNotEmpty)
                    _InfoTile('Notes', col.notes!),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
    ];
  }

  /// Lender Information card.
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
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  SizedBox(height: 14),
                  _InfoTile('Name',
                      col.lenderName.isEmpty ? 'N/A' : col.lenderName),
                  _InfoTile('Loan #',
                      col.loanNumber.isEmpty ? 'N/A' : col.loanNumber),
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
                            width: 110,
                            child: Text('Address',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.cTextSecondary))),
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
                              ].where((e) => e != null && (e as String).isNotEmpty).join(', ');
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
          if (col.status == 'assigned') ...[
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final ok = await ref
                          .read(riderCollectionProvider.notifier)
                          .decline(widget.collectionId);
                      if (mounted && ok) context.pop();
                    },
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error),
                        minimumSize: const Size(0, 48),
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
                    onPressed: () =>
                        ref.read(riderCollectionProvider.notifier).accept(widget.collectionId),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.riderGreen,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 8),
    ];
  }

  /// Dating Step 2 (Collect) content — ngayon ay nasa loob na ng Step 1.
  /// Listahan ito ng widgets para direkta nang isingit sa `_buildDetailsTab`.
  List<Widget> _collectCards(CollectionAssignmentModel col) {
    final schedule = col.loanSchedule;
    final amountDue = (schedule?['amount_due'] as num?)?.toDouble() ?? 0;
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
                border: Border.all(
                    color: AppColors.riderGreen.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      color: AppColors.riderGreen, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Already recorded: ${col.amountCollected!.toCurrency} — you can edit or continue.',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.riderGreen)),
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
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      // Comma separator habang nagta-type: 32000 -> 32,000.
                      inputFormatters: const [
                        ThousandsSeparatorInputFormatter()
                      ],
                      prefixIcon: Icons.payments_outlined,
                      enabled: !alreadyRecorded),
                  SizedBox(height: 14),
                  Text('Notes (optional)',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.cTextSecondary)),
                  SizedBox(height: 6),
                  AppTextField(
                      controller: _notesCtrl,
                      label: 'Notes',
                      hint: 'Any notes about the collection...',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      maxLines: 3,
                      prefixIcon: Icons.sticky_note_2_outlined),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          // Quick actions — hidden once recorded (backend has no re-record;
          // editing the amount after record would be silently discarded).
          if (!alreadyRecorded)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _amountCtrl.text =
                        ThousandsSeparatorInputFormatter.format(amountDue),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.riderGreen,
                    side: BorderSide(color: AppColors.riderGreen),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Use Due Amount',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _amountCtrl.clear(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.cTextSecondary,
                    side: BorderSide(color: context.cBorder),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Clear',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          // Back + Next — dating nasa bottom bar; nasa ibaba na ng "Clear".
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
                // Pantay ang lapad ng Back at Next — gaya ng Use Due Amount
                // at Clear row.
                child: ElevatedButton(
                  onPressed: alreadyRecorded
                      ? () => _goToStep(1)
                      : (!hasAmount || _isSubmitting)
                          ? null
                          : () => _recordAndNext(col),
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
                                style:
                                    TextStyle(fontWeight: FontWeight.w700)),
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
                  Icon(Icons.verified_outlined,
                      size: 40, color: Colors.white),
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
                      style:
                          TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),
            SizedBox(height: 16),
            AppButton(                label: 'Go to Review',
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

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.riderGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.riderGreen.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.camera_alt_outlined,
                    color: AppColors.riderGreen, size: 20),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Upload payment proof & scene photo. These will be reviewed before completing.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.riderGreen,
                            fontWeight: FontWeight.w600,
                            height: 1.3))),
              ],
            ),
          ),
          SizedBox(height: 14),
          if (needCollectFirst)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3))),
              child: Row(
                children: [
                  Icon(Icons.lock_outline,
                      color: AppColors.warning, size: 18),
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
                    child: Text('Go to Collect',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          if (!needCollectFirst) ...[
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
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
                      Text('Payment Proof *',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.cTextPrimary)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                      'Clear photo of receipt or cash — required',
                      style: TextStyle(
                          fontSize: 11, color: context.cTextSecondary)),
                  SizedBox(height: 12),
                  _PhotoPicker(
                    photo: _proofPhoto,
                    onPickCamera: () => _pickImage(true),
                    onPickGallery: () => _pickImageGallery(true),
                    onRemove: () => setState(() => _proofPhoto = null),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14),
            // Signature pad card
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
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
                      Text('Lender Signature (optional)',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.cTextPrimary)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text('Ask lender to sign below',
                      style: TextStyle(
                          fontSize: 11, color: context.cTextSecondary)),
                  SizedBox(height: 12),
                  SignaturePad(
                    height: 140,
                    onSignatureChanged: (base64) =>
                        setState(() => _signatureBase64 = base64),
                  ),
                  if (_signatureBase64 != null)
                    Container(
                      margin: EdgeInsets.only(top: 8),
                      padding: EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle,
                              color: AppColors.riderGreen, size: 14),
                          SizedBox(width: 6),
                          Text('Signature captured',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.riderGreen,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 14),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
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
                      Icon(Icons.camera_outdoor_outlined,
                          color: AppColors.riderGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Scene Photo (optional)',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.cTextPrimary)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text('Photo of collection scene for verification',
                      style: TextStyle(
                          fontSize: 11, color: context.cTextSecondary)),
                  SizedBox(height: 12),
                  _PhotoPicker(
                    photo: _scenePhoto,
                    onPickCamera: () => _pickImage(false),
                    onPickGallery: () => _pickImageGallery(false),
                    onRemove: () => setState(() => _scenePhoto = null),
                    isSmall: true,
                  ),
                ],
              ),
            ),
            SizedBox(height: 14),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.riderGreen.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Icon(Icons.gps_fixed, color: AppColors.riderGreen, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'GPS coordinates are automatically captured and attached to all uploaded photos.',
                      style: TextStyle(
                          fontSize: 11, color: context.cTextSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildReviewTab(CollectionAssignmentModel col) {
    final schedule = col.loanSchedule;
    final amountDue = (schedule?['amount_due'] as num?)?.toDouble() ?? 0;
    final collectedStr = col.amountCollected?.toCurrency ??
        (_amountCtrl.text.isEmpty ? '—' : '₱${_amountCtrl.text}');
    final notesStr = col.notes ?? _notesCtrl.text;
    final isCompleted = col.status == 'completed';

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppColors.successLight
                  : AppColors.riderGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isCompleted
                      ? AppColors.riderGreen.withValues(alpha: 0.2)
                      : AppColors.riderGreen.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(
                    isCompleted
                        ? Icons.verified_outlined
                        : Icons.rate_review_outlined,
                    color: AppColors.riderGreen,
                    size: 20),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                        isCompleted
                            ? 'Collection completed — review your submission below.'
                            : 'Review everything before final submit. Check amount, notes, and proofs.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.riderGreen,
                            fontWeight: FontWeight.w600,
                            height: 1.3))),
              ],
            ),
          ),
          SizedBox(height: 14),
          // Summary card
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
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
                    Icon(Icons.summarize_outlined,
                        color: AppColors.riderGreen, size: 18),
                    SizedBox(width: 8),
                    Text('Review Summary',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                Divider(height: 20),
                _ReviewRow('Lender', col.lenderName.isEmpty ? '—' : col.lenderName),
                _ReviewRow('Loan #', col.loanNumber.isEmpty ? '—' : col.loanNumber),
                _ReviewRow('Due Date', schedule?['due_date'] ?? '—'),
                _ReviewRow('Amount Due', amountDue.toCurrency,
                    valueColor: context.cTextPrimary, valueBold: true),
                SizedBox(height: 6),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.riderGreen.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.riderGreen.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Amount Collected',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.riderGreen,
                              fontWeight: FontWeight.w600)),
                      Text(collectedStr,
                          style: TextStyle(
                              fontSize: 16,
                              color: AppColors.riderGreen,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                _ReviewRow('Notes', notesStr.isEmpty ? 'No notes' : notesStr),
                _ReviewRow('Status', col.statusLabel),
                if (col.completedAt != null)
                  _ReviewRow(
                      'Completed',
                      DateFormat('MMM d, yyyy h:mm a')
                          .format(col.completedAt!)),
              ],
            ),
          ),
          SizedBox(height: 12),
          // Proof preview card
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
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
                    Icon(Icons.photo_library_outlined,
                        color: AppColors.riderGreen, size: 18),
                    SizedBox(width: 8),
                    Text('Proofs',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                SizedBox(height: 12),
                if (_proofPhoto != null) ...[
                  Text('Payment Proof',
                      style: TextStyle(
                          fontSize: 11,
                          color: context.cTextSecondary,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: XFilePreview(
                        file: _proofPhoto!, height: 160, width: double.infinity),
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: AppColors.riderGreen, size: 12),
                      SizedBox(width: 4),
                      Text('Ready to upload — GPS tagged',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.riderGreen)),
                    ],
                  ),
                  SizedBox(height: 14),
                ] else
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: AppColors.error, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                'Payment proof missing — go back to Proof step and capture it.',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.error))),
                      ],
                    ),
                  ),
                if (_scenePhoto != null) ...[
                  SizedBox(height: 10),
                  Text('Scene Photo',
                      style: TextStyle(
                          fontSize: 11,
                          color: context.cTextSecondary,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: XFilePreview(
                        file: _scenePhoto!, height: 140, width: double.infinity),
                  ),
                ],
                if (_signatureBase64 != null) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.draw_outlined,
                            color: AppColors.riderGreen, size: 14),
                        SizedBox(width: 6),
                        Text('Lender signature captured',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.riderGreen,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ] else
                  Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('No signature — optional',
                        style: TextStyle(
                            fontSize: 11, color: context.cTextTertiary)),
                  ),
                SizedBox(height: 10),
                // Edit CTA
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _goToStep(1),
                        icon: Icon(Icons.edit_outlined, size: 16),
                        label: Text('Edit Proofs',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.riderGreen,
                          side: BorderSide(color: AppColors.riderGreen),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _goToStep(0),
                        icon: Icon(Icons.payments_outlined, size: 16),
                        label: Text('Edit Amount',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.cTextSecondary,
                          side: BorderSide(color: context.cBorder),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 14),
          // Checklist
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F9F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.cBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Checklist before submit',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                SizedBox(height: 10),
                _CheckItem(
                    done: (col.amountCollected != null ||
                        _amountCtrl.text.isNotEmpty),
                    label: 'Amount entered'),
                _CheckItem(done: _proofPhoto != null, label: 'Payment proof captured'),
                _CheckItem(
                    done: _signatureBase64 != null,
                    label: 'Signature (optional)',
                    optional: true),
                _CheckItem(
                    done: _scenePhoto != null,
                    label: 'Scene photo (optional)',
                    optional: true),
              ],
            ),
          ),
          SizedBox(height: 80),
        ],
      ),
    );
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
          SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12, color: context.cTextSecondary))),
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
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11, color: context.cTextSecondary))),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: valueBold ? FontWeight.w700 : FontWeight.w600,
                    color: valueColor ?? context.cTextPrimary)),
          ),
        ],
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final bool done;
  final String label;
  final bool optional;
  const _CheckItem(
      {required this.done, required this.label, this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: done
                  ? AppColors.riderGreen
                  : optional
                      ? context.cTextTertiary
                      : AppColors.warning),
          SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: done
                      ? AppColors.riderGreen
                      : optional
                          ? context.cTextTertiary
                          : context.cTextSecondary,
                  fontWeight: done ? FontWeight.w600 : FontWeight.w500)),
          if (optional)
            Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text('(optional)',
                  style: TextStyle(fontSize: 11, color: context.cTextTertiary)),
            )
        ],
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final XFile? photo;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final VoidCallback onRemove;
  final bool isSmall;
  const _PhotoPicker(
      {required this.photo,
      required this.onPickCamera,
      required this.onPickGallery,
      required this.onRemove,
      this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    if (photo != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: XFilePreview(
                file: photo!, height: isSmall ? 140 : 180, width: double.infinity),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: EdgeInsets.all(6),
                decoration:
                    BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.riderGreen,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text('GPS Tagged',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _PickBtn(
              icon: Icons.camera_alt,
              label: 'Camera',
              color: AppColors.riderGreen,
              onTap: onPickCamera),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _PickBtn(
              icon: Icons.photo_library_outlined,
              label: 'Gallery',
              color: AppColors.info,
              onTap: onPickGallery),
        ),
      ],
    );
  }
}

class _PickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PickBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
