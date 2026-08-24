// ignore_for_file: unused_element
// lib/presentation/features/rider/collections/screens/rider_collection_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/constants/route_constants.dart';
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

  // Step labels
  static const _steps = ['Details', 'Collect', 'Proof', 'Review'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _amountCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(riderCollectionProvider.notifier)
          .loadDetails(widget.collectionId);
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
          // Success — auto next to Proof (2)
          _goToStep(2);
          context.showSnackBarAsToast(
            const SnackBar(
              content: Text('Amount recorded — upload proof next'),
              backgroundColor: AppColors.riderGreen,
            ),
          );
        } else {
          showDialog(
              context: context,
              builder: (_) =>
                  const ErrorDialog(message: 'Failed to record collection'));
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
    _goToStep(3);
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
          const SnackBar(content: Text('Amount is missing — go back to Collect step')),
        );
        _goToStep(1);
        return;
      }
    }

    if (_proofPhoto == null) {
      context.showSnackBarAsToast(
          const SnackBar(content: Text('Please add payment proof in Proof step')));
      _goToStep(2);
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
      // If still need to record amount, do it first
      if (!hasCollectedAmount && pendingAmount != null) {
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
          if (mounted) {
            showDialog(
                context: context,
                builder: (_) =>
                    const ErrorDialog(message: 'Failed to record amount'));
          }
          return;
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
          showDialog(
              context: context,
              builder: (_) =>
                  const ErrorDialog(message: 'Failed to upload proof'));
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool _canAccessStep(int stepIndex, CollectionAssignmentModel col) {
    // Details always
    if (stepIndex == 0) return true;
    // Collect requires accepted/in_progress/completed (not assigned)
    if (stepIndex == 1) {
      return col.status == 'accepted' ||
          col.status == 'in_progress' ||
          col.status == 'completed';
    }
    // Proof requires collect done OR status in_progress/completed, or amount entered locally
    if (stepIndex == 2) {
      if (col.status == 'completed') return true;
      if (col.status == 'in_progress') return true;
      if (col.status == 'accepted') {
        // Allow if amount already typed or already collected
        return col.amountCollected != null || _amountCtrl.text.isNotEmpty;
      }
      return false;
    }
    // Review requires Proof captured or completed
    if (stepIndex == 3) {
      if (col.status == 'completed') return true;
      return _proofPhoto != null;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCollectionProvider);
    final col = state.selectedCollection;

    // Sync amount/notes if loaded and controllers empty
    if (col != null) {
      if (_amountCtrl.text.isEmpty && col.amountCollected != null) {
        _amountCtrl.text = col.amountCollected!.toStringAsFixed(2);
      }
      if (_notesCtrl.text.isEmpty && col.notes != null) {
        _notesCtrl.text = col.notes!;
      }
    }

    try {
      // Show provider error (e.g. parseBool failure) explicitly instead of silent "not found"
      if (state.error != null && col == null && !state.isLoading) {
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            backgroundColor: AppColors.riderGreen,
            foregroundColor: Colors.white,
            title: const Text('Collection',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  const Text('Failed to load collection',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(state.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.read(riderCollectionProvider.notifier).loadDetails(widget.collectionId),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.riderGreen),
                    child: const Text('Retry', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: AppColors.riderGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Collection',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          actions: [
            if (col != null)
              Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(child: StatusBadge(status: col.status, small: false))),
          ],
        ),
        body: state.isLoading
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
                        final isReadOnly = col.status == 'completed' ||
                            col.status == 'declined' ||
                            col.status == 'failed';
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
                            _buildStepperHeader(col),
                            Expanded(
                              child: TabBarView(
                                controller: _tabController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _buildDetailsTab(col),
                                  _buildCollectTab(col),
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
                          padding: const EdgeInsets.all(16),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                const Icon(Icons.bug_report, color: AppColors.error, size: 36),
                                const SizedBox(height: 8),
                                Text('Build error: $e',
                                    style: const TextStyle(color: AppColors.error, fontSize: 12)),
                                const SizedBox(height: 8),
                                Text(st.toString(),
                                    style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
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
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: AppColors.riderGreen, foregroundColor: Colors.white, title: const Text('Collection')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Icon(Icons.bug_report, color: AppColors.error, size: 36),
                  const SizedBox(height: 8),
                  Text('Outer build error: $e', style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(st.toString(), style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildStepperHeader(CollectionAssignmentModel col) {
    final current = _tabController.index;
    final isCompletedOverall = col.status == 'completed';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        children: [
          Row(
            children: List.generate(_steps.length, (i) {
              final isActive = i == current;
              final isPast = i < current || isCompletedOverall;
              final canAccess = _canAccessStep(i, col) || isPast;
              final isLocked = !canAccess && !isPast && !isActive;

              return Expanded(
                child: GestureDetector(
                  onTap: canAccess ? () => _goToStep(i) : null,
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // connector line
                          if (i != _steps.length - 1)
                            Positioned(
                              left: 30,
                              right: -30,
                              top: 14,
                              child: Container(
                                height: 2,
                                color: i < current || isCompletedOverall
                                    ? AppColors.riderGreen
                                    : const Color(0xFFE0E0E0),
                              ),
                            ),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: isPast || isCompletedOverall
                                  ? AppColors.riderGreen
                                  : isActive
                                      ? AppColors.riderGreen
                                      : isLocked
                                          ? const Color(0xFFF0F0F0)
                                          : const Color(0xFFF0F0F0),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isActive
                                    ? AppColors.riderGreenDark
                                    : isPast || isCompletedOverall
                                        ? AppColors.riderGreen
                                        : isLocked
                                            ? const Color(0xFFE0E0E0)
                                            : const Color(0xFFE0E0E0),
                                width: isActive ? 2 : 1.5,
                              ),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                          color: AppColors.riderGreen
                                              .withValues(alpha: 0.25),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2))
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: isPast || isCompletedOverall
                                  ? const Icon(Icons.check,
                                      size: 16, color: Colors.white)
                                  : isLocked
                                      ? const Icon(Icons.lock_outline,
                                          size: 14,
                                          color: AppColors.textTertiary)
                                      : Text(
                                          '${i + 1}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: isActive
                                                ? Colors.white
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _steps[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive
                              ? AppColors.riderGreen
                              : isPast || isCompletedOverall
                                  ? AppColors.riderGreen
                                  : isLocked
                                      ? AppColors.textTertiary
                                      : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (current + 1) / _steps.length,
              minHeight: 4,
              backgroundColor: const Color(0xFFE8E8E8),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.riderGreen),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step ${current + 1} of ${_steps.length}: ${_steps[current]}',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500),
              ),
              if (col.status == 'completed')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified,
                          size: 12, color: AppColors.riderGreen),
                      SizedBox(width: 4),
                      Text('Completed',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.riderGreen,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(CollectionAssignmentModel col) {
    final idx = _tabController.index;
    final isFirst = idx == 0;
    final isLast = idx == _steps.length - 1;
    final isCompleted = col.status == 'completed';

    // Hide bottom nav for completed? Keep but show Done.
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          if (!isFirst)
            Expanded(
              child: OutlinedButton(
                onPressed: () => _goToStep(idx - 1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back'),
              ),
            ),
          if (!isFirst) const SizedBox(width: 12),
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
        child: const Text('Done',
            style: TextStyle(fontWeight: FontWeight.w700)),
      );
    }

    // Step-specific primary
    switch (idx) {
      case 0: // Details
        if (col.status == 'assigned') {
          // Show accept/decline already handled inside tab; primary is Next disabled until accepted
          return ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.riderGreen.withValues(alpha: 0.3),
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Accept to continue',
                style: TextStyle(color: Colors.white)),
          );
        }
        // If accepted/in_progress, primary is Continue to Collect
        final canContinue = col.status == 'accepted' || col.status == 'in_progress';
        return ElevatedButton(
          onPressed: canContinue ? () => _goToStep(1) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.riderGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Continue to Collect',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        );
      case 1: // Collect
        final hasAmount = _amountCtrl.text.isNotEmpty;
        final alreadyRecorded = col.amountCollected != null || col.status == 'in_progress';
        if (alreadyRecorded) {
          return ElevatedButton(
            onPressed: () => _goToStep(2),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.riderGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Continue to Proof',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward, size: 18),
              ],
            ),
          );
        }
        return ElevatedButton(
          onPressed: !hasAmount
              ? null
              : () {
                  final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
                  if (amount == null || amount <= 0) {
                    context.showSnackBarAsToast(const SnackBar(content: Text('Please enter a valid amount')));
                    return;
                  }
                  _goToStep(2);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.riderGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Continue to Proof',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        );
      case 2: // Proof
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
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Continue to Review',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        );
      case 3: // Review
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
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Row(
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: col.status == 'completed'
                ? AppColors.riderGreen
                : AppColors.textSecondary,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            col.status == 'completed' ? 'Done' : 'Back to Collections',
            style: const TextStyle(fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Success banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [AppColors.riderGreen, AppColors.riderGreenDark]),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Column(
              children: [
                const Icon(Icons.verified, size: 42, color: Colors.white),
                const SizedBox(height: 10),
                const Text('Collection Completed',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  col.amountCollected != null
                      ? col.amountCollected!.toCurrency
                      : '₱0.00',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Amount collected from lender',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12),
                ),
                if (col.completedAt != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      DateFormat('MMM d, yyyy  •  h:mm a')
                          .format(col.completedAt!),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Summary card - same idea as wizard Details tab but read-only
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          color: AppColors.riderGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Collection Summary',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const Divider(height: 20),
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
          const SizedBox(height: 12),
          // Lender info card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.person_outline,
                          color: AppColors.riderGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Lender Information',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _InfoTile('Name',
                      col.lenderName.isEmpty ? 'N/A' : col.lenderName),
                  _InfoTile('Loan #',
                      col.loanNumber.isEmpty ? 'N/A' : col.loanNumber),
                  _InfoTile(
                      'Phone',
                      (col.loanSchedule?['loan']?['lender_profiles']?['users']
                                  ?['phone_number'] as String?) ??
                          (col.lenderPhone.isEmpty ? 'N/A' : col.lenderPhone)),
                  if (col.lenderAddresses.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Address',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    ...col.lenderAddresses.take(2).map((a) {
                      final m = a as Map<String, dynamic>;
                      final full = [
                        m['street'],
                        m['barangay'],
                        m['city'],
                        m['province']
                      ].where((e) => e != null && (e as String).isNotEmpty).join(', ');
                      final type = (m['address_type'] as String? ?? '').toUpperCase();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.riderGreen
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(type.isEmpty ? 'HOME' : type,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.riderGreen)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(full.isEmpty ? '—' : full,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textPrimary))),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Proof viewer - read only, show stored URLs
          if (col.proofPhoto != null ||
              col.collectionPhoto != null ||
              col.borrowerSignature != null)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.photo_library_outlined,
                            color: AppColors.riderGreen, size: 18),
                        SizedBox(width: 8),
                        Text('Collection Proof',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Photos and signature submitted for this collection',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    if (col.proofPhoto != null) ...[
                      const Text('Payment Proof',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DocumentViewer(
                          url: col.proofPhoto,
                          label: 'Payment Proof',
                          height: 200,
                          bucket: 'collection-proofs'),
                      const SizedBox(height: 14),
                    ],
                    if (col.collectionPhoto != null) ...[
                      const Text('Scene Photo',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DocumentViewer(
                          url: col.collectionPhoto,
                          label: 'Scene Photo',
                          height: 180,
                          bucket: 'collection-proofs'),
                      const SizedBox(height: 14),
                    ],
                    if (col.borrowerSignature != null) ...[
                      const Text('Lender Signature',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceGray,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppColors.textSecondary, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text('No proof photos stored for this collection.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary))),
                ],
              ),
            ),
          if (col.locationLat != null && col.locationLng != null) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            color: AppColors.riderGreen, size: 18),
                        SizedBox(width: 8),
                        Text('Collection Location',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const Divider(height: 20),
                    Text(
                      'Lat: ${col.locationLat!.toStringAsFixed(6)}, Lng: ${col.locationLng!.toStringAsFixed(6)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Receipt decoration
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.riderGreen.withValues(alpha: 0.15)),
            ),
            child: const Row(
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
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildDeclinedBody(CollectionAssignmentModel col) {
    final schedule = col.loanSchedule;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
            ),
            child: const Column(
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
                        TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Details',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const Divider(height: 20),
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
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Details Tab ──────────────────────────────────────────────────────────
  Widget _buildDetailsTab(CollectionAssignmentModel col) {
    final schedule = col.loanSchedule;
    final amountDue = (schedule?['amount_due'] as num?)?.toDouble() ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header summary with gradient + stepper hint
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.riderGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.receipt_long_outlined,
                            color: AppColors.riderGreen, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text('Collection Summary',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      StatusBadge(status: col.status, small: true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        AppColors.riderGreen,
                        AppColors.riderGreenDark
                      ]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.payments_outlined,
                            color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Amount Due',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            Text(amountDue.toCurrency,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.verified_user_outlined,
                            color: Colors.white54, size: 20),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.person_outline,
                          color: AppColors.riderGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Lender Information',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _InfoTile('Name',
                      col.lenderName.isEmpty ? 'N/A' : col.lenderName),
                  _InfoTile('Loan #',
                      col.loanNumber.isEmpty ? 'N/A' : col.loanNumber),
                  _InfoTile(
                      'Phone',
                      (col.loanSchedule?['loan']?['lender_profiles']?['users']
                                  ?['phone_number'] as String?) ??
                          (col.lenderPhone.isEmpty ? 'N/A' : col.lenderPhone)),
                  if (col.lenderAddresses.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Address',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    ...col.lenderAddresses.take(2).map((a) {
                      final m = a as Map<String, dynamic>;
                      final full = [
                        m['street'],
                        m['barangay'],
                        m['city'],
                        m['province']
                      ].where((e) => e != null && (e as String).isNotEmpty).join(', ');
                      final type = (m['address_type'] as String? ?? '').toUpperCase();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.riderGreen
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(type.isEmpty ? 'HOME' : type,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.riderGreen)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(full.isEmpty ? '—' : full,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textPrimary))),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          // Step hint banner for auto-next
          if (col.status == 'accepted' || col.status == 'in_progress')
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.riderGreen.withValues(alpha: 0.18)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome,
                      color: AppColors.riderGreen, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Assignment accepted — tap “Continue to Collect” below to enter amount.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.riderGreen,
                          fontWeight: FontWeight.w500,
                          height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          if (col.status == 'assigned') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'Accept this assignment to enable Collect & Proof steps.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.warning))),
                ],
              ),
            ),
            const SizedBox(height: 14),
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
                        side: const BorderSide(color: AppColors.error),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final ok = await ref
                          .read(riderCollectionProvider.notifier)
                          .accept(widget.collectionId);
                      if (mounted && ok) {
                        _goToStep(1);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.riderGreen,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
          if (col.status == 'accepted' || col.status == 'in_progress') ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push(
                    RouteConstants.riderNavigateToBorrower
                        .replaceFirst(':id', widget.collectionId)),
                icon: const Icon(Icons.navigation_outlined, size: 18),
                label: const Text('Navigate to Lender',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.info,
                  side: const BorderSide(color: AppColors.info),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => context.push(
                    RouteConstants.riderBorrowerInfo
                        .replaceFirst(':id', widget.collectionId)),
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: const Text('View Lender Full Info'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.riderGreen,
                ),
              ),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildCollectTab(CollectionAssignmentModel col) {
    if (col.status == 'completed') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.successLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle,
                    size: 40, color: AppColors.riderGreen),
              ),
              const SizedBox(height: 14),
              const Text('Collection already completed',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text('Amount: ${col.amountCollected?.toCurrency ?? '—'}',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              AppButton(
                label: 'Continue to Proof',
                onPressed: () => _goToStep(2),
                color: AppColors.riderGreen,
              ),
            ],
          ),
        ),
      );
    }
    if (col.status == 'declined') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block_outlined, size: 48, color: AppColors.error),
              SizedBox(height: 12),
              Text('This collection was declined.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }
    if (col.status != 'accepted' && col.status != 'in_progress') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.lock_outline,
                    size: 28, color: AppColors.warning),
              ),
              const SizedBox(height: 14),
              const Text('Accept assignment first',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text(
                  'You must accept the assignment in Details step before recording a collection.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _goToStep(0),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.riderGreen,
                  side: const BorderSide(color: AppColors.riderGreen),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Go to Details'),
              ),
            ],
          ),
        ),
      );
    }

    final schedule = col.loanSchedule;
    final amountDue = (schedule?['amount_due'] as num?)?.toDouble() ?? 0;
    final alreadyRecorded = col.amountCollected != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step intro
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.riderGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.riderGreen.withValues(alpha: 0.15)),
            ),
            child: const Row(
              children: [
                Icon(Icons.edit_note_outlined,
                    color: AppColors.riderGreen, size: 20),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Step 2 — Record the cash amount collected from lender. GPS will be captured automatically.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.riderGreen,
                            fontWeight: FontWeight.w600,
                            height: 1.3))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.riderGreen.withValues(alpha: 0.18))),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.riderGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('Expected amount: ${amountDue.toCurrency}',
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.riderGreen,
                            fontWeight: FontWeight.w700))),
                if (alreadyRecorded)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.riderGreen,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Recorded',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          if (alreadyRecorded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.riderGreen.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.riderGreen, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Already recorded: ${col.amountCollected!.toCurrency} — you can edit or continue.',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.riderGreen)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Collection Details',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 14),
                  AppTextField(
                      controller: _amountCtrl,
                      label: 'Amount Collected (₱) *',
                      hint: '0.00',
                      keyboardType: TextInputType.number,
                      prefixIcon: Icons.payments_outlined),
                  const SizedBox(height: 14),
                  AppTextField(
                      controller: _notesCtrl,
                      label: 'Notes (optional)',
                      hint: 'Any notes about the collection...',
                      maxLines: 3,
                      prefixIcon: Icons.sticky_note_2_outlined),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.riderGreen.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.riderGreen.withValues(alpha: 0.15)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.gps_fixed,
                            color: AppColors.riderGreen, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'GPS location is automatically captured and recorded with this collection.',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Quick actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _amountCtrl.text =
                      amountDue.toStringAsFixed(2),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.riderGreen,
                    side: const BorderSide(color: AppColors.riderGreen),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Use Due Amount',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _amountCtrl.clear(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Clear',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildProofTab(CollectionAssignmentModel col) {
    if (col.status == 'completed') {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.riderGreen, AppColors.riderGreenDark]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.verified_outlined,
                      size: 40, color: Colors.white),
                  const SizedBox(height: 10),
                  const Text('Collection completed!',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    'Amount: ${col.amountCollected?.toCurrency ?? '—'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  if (col.completedAt != null)
                    Text(
                      'Completed: ${DateFormat('MMM d, yyyy h:mm a').format(col.completedAt!)}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Go to Review',
              onPressed: () => _goToStep(3),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.riderGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.riderGreen.withValues(alpha: 0.15)),
            ),
            child: const Row(
              children: [
                Icon(Icons.camera_alt_outlined,
                    color: AppColors.riderGreen, size: 20),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Step 3 — Upload payment proof & scene photo. These will be reviewed before completing.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.riderGreen,
                            fontWeight: FontWeight.w600,
                            height: 1.3))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (needCollectFirst)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3))),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                      child: Text(
                          'Record the collected amount in Collect step first before uploading proof.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                              height: 1.3))),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _goToStep(1),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Go to Collect',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          if (!needCollectFirst) ...[
            Container(
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
                      Icon(Icons.receipt_long_outlined,
                          color: AppColors.riderGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Payment Proof *',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                      'Clear photo of receipt or cash — required',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  _PhotoPicker(
                    photo: _proofPhoto,
                    onPickCamera: () => _pickImage(true),
                    onPickGallery: () => _pickImageGallery(true),
                    onRemove: () => setState(() => _proofPhoto = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Signature pad card
            Container(
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
                      Icon(Icons.draw_outlined,
                          color: AppColors.riderGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Lender Signature (optional)',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Ask lender to sign below',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  SignaturePad(
                    height: 140,
                    onSignatureChanged: (base64) =>
                        setState(() => _signatureBase64 = base64),
                  ),
                  if (_signatureBase64 != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
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
            const SizedBox(height: 14),
            Container(
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
                      Icon(Icons.camera_outdoor_outlined,
                          color: AppColors.riderGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Scene Photo (optional)',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Photo of collection scene for verification',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.riderGreen.withValues(alpha: 0.18)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.gps_fixed, color: AppColors.riderGreen, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'GPS coordinates are automatically captured and attached to all uploaded photos.',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 80),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
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
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        isCompleted
                            ? 'Collection completed — review your submission below.'
                            : 'Step 4 — Review everything before final submit. Check amount, notes, and proofs.',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.riderGreen,
                            fontWeight: FontWeight.w600,
                            height: 1.3))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Summary card
          Container(
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
                    Icon(Icons.summarize_outlined,
                        color: AppColors.riderGreen, size: 18),
                    SizedBox(width: 8),
                    Text('Review Summary',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const Divider(height: 20),
                _ReviewRow('Lender', col.lenderName.isEmpty ? '—' : col.lenderName),
                _ReviewRow('Loan #', col.loanNumber.isEmpty ? '—' : col.loanNumber),
                _ReviewRow('Due Date', schedule?['due_date'] ?? '—'),
                _ReviewRow('Amount Due', amountDue.toCurrency,
                    valueColor: AppColors.textPrimary, valueBold: true),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.riderGreen.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.riderGreen.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Amount Collected',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.riderGreen,
                              fontWeight: FontWeight.w600)),
                      Text(collectedStr,
                          style: const TextStyle(
                              fontSize: 16,
                              color: AppColors.riderGreen,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
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
          const SizedBox(height: 12),
          // Proof preview card
          Container(
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
                    Icon(Icons.photo_library_outlined,
                        color: AppColors.riderGreen, size: 18),
                    SizedBox(width: 8),
                    Text('Proofs',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
                if (_proofPhoto != null) ...[
                  const Text('Payment Proof',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: XFilePreview(
                        file: _proofPhoto!, height: 160, width: double.infinity),
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: AppColors.riderGreen, size: 12),
                      SizedBox(width: 4),
                      Text('Ready to upload — GPS tagged',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.riderGreen)),
                    ],
                  ),
                  const SizedBox(height: 14),
                ] else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.25)),
                    ),
                    child: const Row(
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
                  const SizedBox(height: 10),
                  const Text('Scene Photo',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: XFilePreview(
                        file: _scenePhoto!, height: 140, width: double.infinity),
                  ),
                ],
                if (_signatureBase64 != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
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
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('No signature — optional',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textTertiary)),
                  ),
                const SizedBox(height: 10),
                // Edit CTA
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _goToStep(2),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit Proofs',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.riderGreen,
                          side: const BorderSide(color: AppColors.riderGreen),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _goToStep(1),
                        icon: const Icon(Icons.payments_outlined, size: 16),
                        label: const Text('Edit Amount',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
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
          const SizedBox(height: 14),
          // Checklist
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F9F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Checklist before submit',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
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
          const SizedBox(height: 80),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary))),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary))),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: valueBold ? FontWeight.w700 : FontWeight.w600,
                    color: valueColor ?? AppColors.textPrimary)),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: done
                  ? AppColors.riderGreen
                  : optional
                      ? AppColors.textTertiary
                      : AppColors.warning),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: done
                      ? AppColors.riderGreen
                      : optional
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                  fontWeight: done ? FontWeight.w600 : FontWeight.w500)),
          if (optional)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text('(optional)',
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
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
                padding: const EdgeInsets.all(6),
                decoration:
                    const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.riderGreen,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
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
        const SizedBox(width: 8),
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
