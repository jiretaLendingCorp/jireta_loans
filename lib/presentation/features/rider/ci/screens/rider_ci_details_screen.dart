// ignore_for_file: unused_element, unused_element_parameter, unused_field
// lib/presentation/features/rider/ci/screens/rider_ci_details_screen.dart
// Wizard CI Details — 3-step flow: Details → Upload & Report → Review & Submit
// Only on Review→Submit does the report become visible to Head Manager / Employee (status: completed)
// Upload + Report merged into single Step 2 (required), deferred upload until Review→Submit
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/error_dialog.dart';
import '../../../../shared/widgets/dialogs/success_dialog.dart';
import '../../../../shared/widgets/image/xfile_preview.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/rider_ci_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Step meta
// ─────────────────────────────────────────────────────────────────────────────
class _StepMeta {
  final String title;
  final String subtitle;
  final IconData icon;
  const _StepMeta(this.title, this.subtitle, this.icon);
}

const _steps = [
  _StepMeta('Details', 'Lender info', Icons.person_outline_rounded),
  _StepMeta('Upload', 'Evidence + Report', Icons.photo_camera_outlined),
  _StepMeta('Review', 'Submit', Icons.verified_outlined),
];

class RiderCiDetailsScreen extends ConsumerStatefulWidget {
  final String ciId;
  const RiderCiDetailsScreen({super.key, required this.ciId});

  @override
  ConsumerState<RiderCiDetailsScreen> createState() =>
      _RiderCiDetailsScreenState();
}

class _RiderCiDetailsScreenState extends ConsumerState<RiderCiDetailsScreen> {
  int _currentStep = 0;
  final _reportCtrl = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<XFile> _pickedImages = [];
  bool _isSubmitting = false;
  bool _didPrefillReport = false;
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(riderCiProvider.notifier).loadDetails(widget.ciId);
      if (mounted) setState(() => _isInitialLoading = false);
    });
    _reportCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reportCtrl.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  CreditInvestigationModel? get _ci => ref.watch(riderCiProvider).selectedCi;

  bool get _isAssigned => _ci?.status == 'assigned';
  bool get _isAccepted =>
      _ci?.status == 'accepted' || _ci?.status == 'in_progress';
  bool get _isCompleted => _ci?.status == 'completed';
  bool get _isDeclined => _ci?.status == 'declined';
  // Display mapping: accepted → in_progress (user req)
  String get _displayStatus {
    final s = _ci?.status ?? 'assigned';
    return s == 'accepted' ? 'in_progress' : s;
  }

  int get _uploadedDocsCount => _ci?.documents?.length ?? 0;
  int get _pendingCount => _pickedImages.length;
  // Effective docs = server docs + pending staged docs (deferred upload until Review→Submit)
  int get _effectiveDocsCount => _uploadedDocsCount + _pendingCount;
  int get _reportLen => _reportCtrl.text.trim().length;
  bool get _hasReport => _reportLen >= 10 && _reportLen <= 5000;
  // DEBUG FIX: upload must NOT succeed before Review Submit, so pending staged docs count toward canSubmit
  // Actual server upload happens atomically inside _submitFinal()
  // Report: min 10, max 600 chars (user req)
  bool get _canSubmit =>
      _isAccepted && _effectiveDocsCount > 0 && _hasReport && !_isCompleted;

  // Step gating — must accept before proceeding past step 0
  bool _canGoToStep(int idx) {
    if (_isCompleted) return true; // allow reviewing completed
    if (idx == 0) return true;
    if (_isAssigned || _isDeclined) return false; // locked until accepted
    return true;
  }

  void _prefillIfNeeded(CreditInvestigationModel ci) {
    if (_didPrefillReport) return;
    if (ci.reportSummary != null && ci.reportSummary!.isNotEmpty) {
      _reportCtrl.text = ci.reportSummary!;
      _didPrefillReport = true;
    } else if (ci.reportSummary == null) {
      // still mark as checked so we don't overwrite user typing on reloads
      _didPrefillReport = true;
    }
  }

  // ── actions ────────────────────────────────────────────────────────────────
  Future<void> _handleAccept() async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Accept Assignment?',
      message:
          'By accepting, you’ll start the investigation wizard. You’ll be guided through Details → Upload → Report → Review. Continue?',
      confirmLabel: 'Accept',
      confirmColor: AppColors.riderGreen,
    );
    if (confirmed != true) return;
    final ok = await ref.read(riderCiProvider.notifier).accept(widget.ciId);
    if (!mounted) return;
    if (ok) {
      context.showSnackBarAsToast(const SnackBar(
          content: Text('Assignment accepted — starting wizard'),
          backgroundColor: AppColors.riderGreen));
      setState(() => _currentStep = 1);
      // reload to reflect status
      await ref.read(riderCiProvider.notifier).loadDetails(widget.ciId);
    } else {
      showDialog(
          context: context,
          builder: (_) =>
              const ErrorDialog(message: 'Failed to accept assignment'));
    }
  }

  Future<void> _handleDecline() async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Decline Assignment?',
      message:
          'Declining will return this CI to the Head Manager for reassignment. Are you sure?',
      confirmLabel: 'Decline',
      confirmColor: AppColors.error,
    );
    if (confirmed != true) return;
    final ok = await ref.read(riderCiProvider.notifier).decline(widget.ciId);
    if (mounted && ok) {
      context.showSnackBarAsToast(const SnackBar(
          content: Text('Assignment declined'), backgroundColor: AppColors.error));
      context.pop();
    }
  }

  Future<void> _pickImages() async {
    // Allow both camera/gallery via bottom sheet for single picks iteratively,
    // but here we use multiImage for speed
    final picked =
        await _imagePicker.pickMultiImage(imageQuality: 80, maxWidth: 1920);
    if (picked.isNotEmpty) setState(() => _pickedImages.addAll(picked));
  }

  Future<void> _pickFromCamera() async {
    final picked = await _imagePicker.pickImage(
        source: ImageSource.camera, imageQuality: 80, maxWidth: 1920);
    if (picked != null) setState(() => _pickedImages.add(picked));
  }

  Future<void> _submitFinal() async {
    if (!_canSubmit) {
      String msg = 'Complete all steps first.';
      if (_effectiveDocsCount == 0) {
        msg = 'Upload at least 1 evidence photo in Step 2 before submitting.';
      } else if (!_hasReport) {
        msg = 'Report must be 10-5000 characters (Step 2).';
      } else if (_isAssigned) {
        msg = 'You must accept the assignment first.';
      }
      if (!mounted) return;
      context.showSnackBarAsToast(SnackBar(
          content: Text(msg), backgroundColor: AppColors.error));
      // jump to the failing step (Step 2 is combined Upload & Report for 3-step wizard)
      if (_effectiveDocsCount == 0 || !_hasReport) {
        setState(() => _currentStep = 1);
      }
      return;
    }

    final confirmed = await showConfirmationDialog(
      context,
      title: 'Submit Report?',
      message:
          'This will mark the investigation as COMPLETED. You can’t edit after this. Submit now?',
      confirmLabel: 'Submit',
      confirmColor: AppColors.riderGreen,
    );
    if (confirmed != true) return;

    // If there are pending local images not yet uploaded, upload first
    if (_pickedImages.isNotEmpty) {
      setState(() => _isSubmitting = true);
      final okUp = await ref.read(riderCiProvider.notifier).uploadDocuments(
            ciId: widget.ciId,
            images: List.from(_pickedImages),
          );
      if (!okUp) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          showDialog(
              context: context,
              builder: (_) => const ErrorDialog(
                  message: 'Failed to upload pending photos. Please try again.'));
        }
        return;
      }
      if (mounted) setState(() => _pickedImages.clear());
      await ref.read(riderCiProvider.notifier).loadDetails(widget.ciId);
    }

    setState(() => _isSubmitting = true);
    try {
      final ok = await ref.read(riderCiProvider.notifier).submitReport(
            ciId: widget.ciId,
            reportSummary: _reportCtrl.text.trim(),
          );
      if (!mounted) return;
      if (ok) {
        await ref.read(riderCiProvider.notifier).loadDetails(widget.ciId);
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => const SuccessDialog(
            title: 'Report Submitted!',
            message: 'Investigation completed. Your report and evidence have been submitted.',
          ),
        );
        if (!mounted) return;
        // stay on review step showing completed state
        setState(() => _currentStep = 3);
      } else {
        if (!mounted) return;
        showDialog(
            context: context,
            builder: (_) => const ErrorDialog(
                message:
                    'Failed to submit report. Ensure at least 1 photo is uploaded and report is valid.'));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _next() {
    if (_currentStep < 2) {
      if (_currentStep == 0 && _isAssigned) {
        context.showSnackBarAsToast(const SnackBar(
            content: Text('Please Accept the assignment first to continue')));
        return;
      }
      if (_currentStep == 1) {
        if (_effectiveDocsCount == 0) {
          context.showSnackBarAsToast(const SnackBar(
              content: Text('Upload at least 1 photo is required')));
          return;
        }
        if (!_hasReport) {
          context.showSnackBarAsToast(SnackBar(
              content: Text(_reportLen < 10
                  ? 'Report must be at least 10 characters'
                  : 'Report must be max 5000 characters'),
              backgroundColor: AppColors.error));
          return;
        }
      }
      setState(() => _currentStep++);
    } else {
      _submitFinal();
    }
  }

  void _prev() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  void _jumpTo(int idx) {
    if (_canGoToStep(idx)) setState(() => _currentStep = idx);
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCiProvider);
    final ci = state.selectedCi;

    // prefill report once when ci loads
    if (ci != null && !_didPrefillReport) {
      // delay setState until next frame to avoid build-time setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _prefillIfNeeded(ci);
          if (_isCompleted && _currentStep != 2) {
            setState(() => _currentStep = 2);
          }
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: AppColors.riderGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('CI Investigation',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        centerTitle: false,
        actions: [
          if (ci != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                  child: StatusBadge(
                      status: ci.status == 'accepted' ? 'in_progress' : ci.status,
                      small: false)),
            ),
        ],
      ),
      body: ci == null
          ? ((_isInitialLoading || state.isLoading)
              ? const ShimmerLoader()
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off_rounded,
                          size: 48, color: AppColors.textTertiary),
                      const SizedBox(height: 12),
                      const Text('CI assignment not found',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: () async {
                            setState(() => _isInitialLoading = true);
                            await ref
                                .read(riderCiProvider.notifier)
                                .loadDetails(widget.ciId);
                            if (context.mounted) {
                              setState(() => _isInitialLoading = false);
                            }
                          },
                          child: const Text('Retry'))
                    ],
                  ),
                ))
              : Column(
                  children: [
                    _WizardHeader(
                      current: _currentStep,
                      isAssigned: _isAssigned,
                      isAccepted: _isAccepted,
                      isCompleted: _isCompleted,
                      isDeclined: _isDeclined,
                      uploadedCount: _effectiveDocsCount,
                      hasReport: _hasReport,
                      onTapStep: _jumpTo,
                    ),
                    _ProgressBar(
                        progress: (_currentStep + 1) / _steps.length),
                    if (_isCompleted)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.riderGreen.withValues(alpha: 0.25)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.verified_rounded,
                                color: AppColors.riderGreen, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'Completed — Report submitted.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.riderGreen))),
                          ],
                        ),
                      ),
                    if (_isDeclined)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.errorLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.25)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.cancel_outlined,
                                color: AppColors.error, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                                child: Text('Declined — this assignment is closed.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.error))),
                          ],
                        ),
                      ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _buildStepContent(ci),
                      ),
                    ),
                    _WizardBottomBar(
                      current: _currentStep,
                      isAssigned: _isAssigned,
                      isCompleted: _isCompleted,
                      isDeclined: _isDeclined,
                      canSubmit: _canSubmit,
                      isSubmitting: _isSubmitting,
                      uploadedCount: _uploadedDocsCount,
                      pendingCount: _pendingCount,
                      hasReport: _hasReport,
                      onPrev: _prev,
                      onNext: _next,
                      onSubmit: _submitFinal,
                    ),
                  ],
                ),
    );
  }

  Widget _buildStepContent(CreditInvestigationModel ci) {
    switch (_currentStep) {
      case 0:
        return _DetailsStep(
          key: const ValueKey(0),
          ci: ci,
          ciId: widget.ciId,
          onAccept: _handleAccept,
          onDecline: _handleDecline,
        );
      case 1:
        return _UploadReportStep(
          key: ValueKey('uploadreport_${widget.ciId}'),
          ci: ci,
          pickedImages: _pickedImages,
          controller: _reportCtrl,
          onPickMulti: _pickImages,
          onPickCamera: _pickFromCamera,
          onRemovePicked: (i) => setState(() => _pickedImages.removeAt(i)),
          onClearPicked: () => setState(() => _pickedImages.clear()),
        );
      case 2:
        return _ReviewStep(
          key: ValueKey('review_${widget.ciId}'),
          ci: ci,
          pickedImages: _pickedImages,
          reportText: _reportCtrl.text,
          isCompleted: _isCompleted,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER & PROGRESS
// ─────────────────────────────────────────────────────────────────────────────
class _WizardHeader extends StatelessWidget {
  final int current;
  final bool isAssigned;
  final bool isAccepted;
  final bool isCompleted;
  final bool isDeclined;
  final int uploadedCount;
  final bool hasReport;
  final void Function(int) onTapStep;
  const _WizardHeader({
    required this.current,
    required this.isAssigned,
    required this.isAccepted,
    required this.isCompleted,
    required this.isDeclined,
    required this.uploadedCount,
    required this.hasReport,
    required this.onTapStep,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        children: [
          Row(
            children: List.generate(_steps.length, (i) {
              final isActive = i == current;
              final isDone = () {
                if (isCompleted) return true;
                if (i == 0) return isAccepted || isCompleted;
                if (i == 1) return uploadedCount > 0 && hasReport;
                return false;
              }();
              final isLocked = !isCompleted && (isAssigned || isDeclined) && i > 0;
              return Expanded(
                child: GestureDetector(
                  onTap: isLocked ? null : () => onTapStep(i),
                  child: Opacity(
                    opacity: isLocked ? 0.45 : 1,
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.riderGreen
                                    : isDone
                                        ? AppColors.riderGreen
                                        : isLocked
                                            ? AppColors.surfaceVariant
                                            : Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isActive || isDone
                                      ? AppColors.riderGreen
                                      : AppColors.border,
                                  width: isActive ? 2 : 1.4,
                                ),
                                boxShadow: isActive
                                    ? [
                                        BoxShadow(
                                            color: AppColors.riderGreen
                                                .withValues(alpha: 0.25),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4))
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                isDone && !isActive
                                    ? Icons.check_rounded
                                    : _steps[i].icon,
                                size: 18,
                                color: isActive || isDone
                                    ? Colors.white
                                    : isLocked
                                        ? AppColors.textTertiary
                                        : AppColors.textSecondary,
                              ),
                            ),
                            if (isLocked)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: const BoxDecoration(
                                      color: AppColors.textTertiary,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.lock_rounded,
                                      size: 8, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(_steps[i].title,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight:
                                    isActive ? FontWeight.w800 : FontWeight.w600,
                                color: isActive
                                    ? AppColors.riderGreen
                                    : isLocked
                                        ? AppColors.textTertiary
                                        : AppColors.textPrimary)),
                        Text(_steps[i].subtitle,
                            style: const TextStyle(
                                fontSize: 9, color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          // connector line with progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: List.generate(_steps.length - 1, (i) {
                final filled = i < current || isCompleted;
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(
                        left: i == 0 ? 0 : 6, right: i == _steps.length - 2 ? 0 : 6),
                    decoration: BoxDecoration(
                      color: filled
                          ? AppColors.riderGreen
                          : AppColors.border.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Text('Step ${current + 1} of ${_steps.length} • ${_steps[current].title}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.2)),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: AppColors.border.withValues(alpha: 0.4),
        valueColor: const AlwaysStoppedAnimation(AppColors.riderGreen),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — DETAILS
// ─────────────────────────────────────────────────────────────────────────────
class _DetailsStep extends StatelessWidget {
  final CreditInvestigationModel ci;
  final String ciId;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _DetailsStep(
      {super.key,
      required this.ci,
      required this.ciId,
      required this.onAccept,
      required this.onDecline});

  @override
  Widget build(BuildContext context) {
    final isAssigned = ci.status == 'assigned';
    final isCompleted = ci.status == 'completed';
    return SingleChildScrollView(
      key: const ValueKey('details_scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          // Lender card — premium
          _PremiumSectionCard(
            title: 'Lender Information',
            subtitle: '',
            icon: Icons.person_rounded,
            accent: AppColors.lenderBlue,
            children: [
              _InfoTile(
                  icon: Icons.badge_outlined,
                  label: 'Name',
                  value: ci.borrowerName.isEmpty ? 'N/A' : ci.borrowerName),
              _InfoTile(
                  icon: Icons.numbers_rounded,
                  label: 'Loan #',
                  value: ci.loanNumber.isEmpty ? 'N/A' : ci.loanNumber),
              _InfoTile(
                  icon: Icons.location_on_outlined,
                  label: 'Address',
                  value: ci.borrowerAddress.isEmpty ? 'N/A' : ci.borrowerAddress),
              _InfoTile(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: ci.borrowerPhone.isEmpty ? 'N/A' : ci.borrowerPhone),
            ],
          ),
          const SizedBox(height: 12),
          _PremiumSectionCard(
            title: 'Assignment Details',
            subtitle: 'Timeline & instructions',
            icon: Icons.assignment_outlined,
            accent: AppColors.riderGreen,
            children: [
              _InfoTile(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Assigned By',
                  value: ci.assignedByName.isEmpty ? 'N/A' : ci.assignedByName),
              _InfoTile(
                  icon: Icons.schedule_rounded,
                  label: 'Assigned At',
                  value: DateFormat('MMM d, yyyy • h:mm a').format(ci.assignedAt)),
              _InfoTile(
                  icon: Icons.event_outlined,
                  label: 'Deadline',
                  value: ci.deadline != null
                      ? DateFormat('MMM d, yyyy').format(ci.deadline!)
                      : 'No deadline',
                  valueColor: ci.deadline != null &&
                          ci.deadline!.isBefore(DateTime.now()) &&
                          !isCompleted
                      ? AppColors.error
                      : null),
              if (ci.investigationNotes != null &&
                  ci.investigationNotes!.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.riderGreen.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.riderGreen.withValues(alpha: 0.15))),
                  child: Text(ci.investigationNotes!,
                      style: const TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.textPrimary)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (isAssigned) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Decline',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Accept',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.riderGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2 — UPLOAD (legacy, kept for reference but unused — merged into _UploadReportStep)
// ─────────────────────────────────────────────────────────────────────────────
class _UploadStep extends StatelessWidget {
  final CreditInvestigationModel ci;
  final List<XFile> pickedImages;
  final VoidCallback onPickMulti;
  final VoidCallback onPickCamera;
  final void Function(int) onRemovePicked;
  final VoidCallback onClearPicked;

  const _UploadStep({
    super.key,
    required this.ci,
    required this.pickedImages,
    required this.onPickMulti,
    required this.onPickCamera,
    required this.onRemovePicked,
    required this.onClearPicked,
  });

  @override
  Widget build(BuildContext context) {
    final uploaded = ci.documents ?? [];
    final hasPending = pickedImages.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Upload Evidence *',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (uploaded.isNotEmpty) ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: uploaded.length,
              itemBuilder: (ctx, i) {
                final doc = uploaded[i];
                final url = (doc['file_url'] as String?) ?? '';
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: url.isNotEmpty
                      ? Image.network(url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: AppColors.surfaceVariant,
                              child: const Icon(Icons.broken_image_outlined,
                                  color: AppColors.textTertiary)))
                      : Container(
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.photo_outlined,
                              color: AppColors.textTertiary)),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          // Pick buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickMulti,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Gallery',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.riderGreen,
                    side: const BorderSide(color: AppColors.riderGreen),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPickCamera,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Camera',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.riderGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          if (hasPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Pending (${pickedImages.length})',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const Spacer(),
                TextButton(
                    onPressed: onClearPicked, child: const Text('Clear all')),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: pickedImages.length,
              itemBuilder: (ctx, i) => Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: XFilePreview(file: pickedImages[i])),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => onRemovePicked(i),
                      child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                              color: AppColors.error, shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white)),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text('NEW',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800)),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 3 — REPORT (legacy, kept for reference but unused — merged into _UploadReportStep)
// ─────────────────────────────────────────────────────────────────────────────
class _ReportStep extends StatelessWidget {
  final CreditInvestigationModel ci;
  final TextEditingController controller;
  final int uploadedCount;
  const _ReportStep(
      {super.key,
      required this.ci,
      required this.controller,
      required this.uploadedCount});

  @override
  Widget build(BuildContext context) {
    final len = controller.text.trim().length;
    final hasMin = len >= 10 && len <= 5000;
    final isCompleted = ci.status == 'completed';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Investigation Report *',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: !hasMin && len > 0
                      ? AppColors.error.withValues(alpha: 0.5)
                      : AppColors.border),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: TextField(
              controller: controller,
              maxLines: 12,
              minLines: 7,
              maxLength: 5000,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              enabled: !isCompleted,
              style: const TextStyle(fontSize: 14, height: 1.5),
              decoration: InputDecoration(
                hintText: 'Enter report',
                hintStyle: TextStyle(
                    fontSize: 12.5, color: AppColors.textTertiary, height: 1.4),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(14),
                counterText: '',
              ),
              buildCounter: (context,
                      {required int currentLength,
                      required bool isFocused,
                      int? maxLength}) =>
                  null,
            ),
          ),
          const SizedBox(height: 8),
          Text('$len / 5000',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hasMin ? AppColors.riderGreen : AppColors.error)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ── COMBINED STEP 2: Upload + Report (required together) ────────────────────
class _UploadReportStep extends StatelessWidget {
  final CreditInvestigationModel ci;
  final List<XFile> pickedImages;
  final TextEditingController controller;
  final VoidCallback onPickMulti;
  final VoidCallback onPickCamera;
  final void Function(int) onRemovePicked;
  final VoidCallback onClearPicked;

  const _UploadReportStep({
    super.key,
    required this.ci,
    required this.pickedImages,
    required this.controller,
    required this.onPickMulti,
    required this.onPickCamera,
    required this.onRemovePicked,
    required this.onClearPicked,
  });

  @override
  Widget build(BuildContext context) {
    final uploaded = ci.documents ?? [];
    final hasPending = pickedImages.isNotEmpty;
    final len = controller.text.trim().length;
    final hasMin = len >= 10 && len <= 5000;
    final isCompleted = ci.status == 'completed';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Upload section ──
          const Text('Upload Evidence *',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (uploaded.isNotEmpty) ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: uploaded.length,
              itemBuilder: (ctx, i) {
                final doc = uploaded[i];
                final url = (doc['file_url'] as String?) ?? '';
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: url.isNotEmpty
                      ? Image.network(url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: AppColors.surfaceVariant,
                              child: const Icon(Icons.broken_image_outlined,
                                  color: AppColors.textTertiary)))
                      : Container(
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.photo_outlined,
                              color: AppColors.textTertiary)),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickMulti,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Gallery',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.riderGreen,
                    side: const BorderSide(color: AppColors.riderGreen),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPickCamera,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Camera',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.riderGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          if (hasPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Pending (${pickedImages.length})',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const Spacer(),
                TextButton(
                    onPressed: onClearPicked, child: const Text('Clear all')),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: pickedImages.length,
              itemBuilder: (ctx, i) => Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: XFilePreview(file: pickedImages[i])),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => onRemovePicked(i),
                      child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                              color: AppColors.error, shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white)),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text('NEW',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── Report section ──
          const Text('Investigation Report *',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: !hasMin && len > 0
                      ? AppColors.error.withValues(alpha: 0.5)
                      : AppColors.border),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: TextField(
              controller: controller,
              maxLines: 12,
              minLines: 7,
              maxLength: 5000,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              enabled: !isCompleted,
              style: const TextStyle(fontSize: 14, height: 1.5),
              decoration: InputDecoration(
                hintText: 'Enter report',
                hintStyle: TextStyle(
                    fontSize: 12.5, color: AppColors.textTertiary, height: 1.4),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(14),
                counterText: '',
              ),
              buildCounter: (context,
                      {required int currentLength,
                      required bool isFocused,
                      int? maxLength}) =>
                  null,
            ),
          ),
          const SizedBox(height: 8),
          Text('$len / 5000',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hasMin ? AppColors.riderGreen : AppColors.error)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 3 — REVIEW & SUBMIT
// ─────────────────────────────────────────────────────────────────────────────
class _ReviewStep extends StatelessWidget {
  final CreditInvestigationModel ci;
  final List<XFile> pickedImages;
  final String reportText;
  final bool isCompleted;

  const _ReviewStep({
    super.key,
    required this.ci,
    required this.pickedImages,
    required this.reportText,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final uploaded = ci.documents ?? [];
    final hasPending = pickedImages.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lender & Assignment — read-only
          _ReviewCard(
            title: 'Lender & Assignment',
            icon: Icons.assignment_ind_rounded,
            color: AppColors.lenderBlue,
            child: Column(
              children: [
                _ReviewTile('Lender', ci.borrowerName.isEmpty ? 'N/A' : ci.borrowerName),
                _ReviewTile('Loan #', ci.loanNumber.isEmpty ? 'N/A' : ci.loanNumber),
                _ReviewTile('Address',
                    ci.borrowerAddress.isEmpty ? 'N/A' : ci.borrowerAddress),
                _ReviewTile('Deadline',
                    ci.deadline != null
                        ? DateFormat('MMM d, yyyy').format(ci.deadline!)
                        : 'N/A'),
                if (ci.investigationNotes != null && ci.investigationNotes!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(ci.investigationNotes!,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Evidence Photos — read-only
          _ReviewCard(
            title: 'Evidence Photos (${uploaded.length})',
            icon: Icons.photo_library_rounded,
            color: AppColors.riderGreen,
            child: uploaded.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('No photos uploaded yet.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF8D6E00))),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                    itemCount: uploaded.length > 6 ? 6 : uploaded.length,
                    itemBuilder: (ctx, i) {
                      final doc = uploaded[i];
                      final url = (doc['file_url'] as String?) ?? '';
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: url.isNotEmpty
                            ? Image.network(url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                    color: AppColors.surfaceVariant,
                                    child: const Icon(Icons.broken_image_outlined,
                                        color: AppColors.textTertiary)))
                            : Container(
                                color: AppColors.surfaceVariant,
                                child: const Icon(Icons.photo_outlined,
                                    color: AppColors.textTertiary)),
                      );
                    },
                  ),
          ),
          if (hasPending) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.2))),
              child: Row(
                children: [
                  const Icon(Icons.pending_actions_rounded,
                      size: 16, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('${pickedImages.length} new photo(s) pending — will be uploaded automatically on Submit.',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary))),
                ],
              ),
            ),
          ],
          if (uploaded.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('+ ${uploaded.length - 6} more photo(s)',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ),
          const SizedBox(height: 12),

          // Investigation Report — read-only
          _ReviewCard(
            title: 'Investigation Report',
            icon: Icons.article_rounded,
            color: const Color(0xFF00838F),
            child: reportText.trim().isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('No report written yet.',
                        style: TextStyle(fontSize: 12, color: AppColors.error)),
                  )
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border.withValues(alpha: 0.5))),
                    child: Text(reportText.trim(),
                        style: const TextStyle(
                            fontSize: 13, height: 1.5, color: AppColors.textPrimary)),
                  ),
          ),
          const SizedBox(height: 14),

          if (isCompleted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.riderGreen.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.celebration_rounded, color: AppColors.riderGreen),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          'Report submitted successfully! No further edits allowed.',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.riderGreen))),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'By submitting, you confirm the report is accurate.',
                          style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: AppColors.textSecondary))),
                ],
              ),
            ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final bool done;
  final String label;
  final String detail;
  final VoidCallback? onFix;
  const _CheckRow(
      {required this.done,
      required this.label,
      required this.detail,
      this.onFix});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: done
                ? AppColors.riderGreen.withValues(alpha: 0.25)
                : AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                color: done ? AppColors.riderGreen : AppColors.warningLight,
                shape: BoxShape.circle),
            child: Icon(done ? Icons.check_rounded : Icons.close_rounded,
                size: 14, color: done ? Colors.white : AppColors.warning),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text(detail,
                    style: TextStyle(
                        fontSize: 11,
                        color: done ? AppColors.textSecondary : AppColors.warning)),
              ],
            ),
          ),
          if (!done && onFix != null)
            TextButton(
                onPressed: onFix,
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.riderGreen,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 32)),
                child: const Text('Fix', style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final VoidCallback? onEdit;
  const _ReviewCard(
      {required this.title,
      required this.icon,
      required this.color,
      required this.child,
      this.onEdit});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, size: 16, color: color)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary))),
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.riderGreen,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 32)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewTile(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM BAR
// ─────────────────────────────────────────────────────────────────────────────
class _WizardBottomBar extends StatelessWidget {
  final int current;
  final bool isAssigned;
  final bool isCompleted;
  final bool isDeclined;
  final bool canSubmit;
  final bool isSubmitting;
  final int uploadedCount;
  final int pendingCount;
  final bool hasReport;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  const _WizardBottomBar({
    required this.current,
    required this.isAssigned,
    required this.isCompleted,
    required this.isDeclined,
    required this.canSubmit,
    required this.isSubmitting,
    required this.uploadedCount,
    required this.pendingCount,
    required this.hasReport,
    required this.onPrev,
    required this.onNext,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final isFirst = current == 0;
    final isLast = current == 2;

    // Completed / Declined — show disabled bar
    if (isCompleted || isDeclined) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, -4))
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.go(RouteConstants.riderCi),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(isCompleted ? 'Back to CI List' : 'Back',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.riderGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (!isFirst)
              Expanded(
                child: OutlinedButton(
                  onPressed: onPrev,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              )
            else
              const Expanded(child: SizedBox()),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: isLast
                  ? ElevatedButton.icon(
                      onPressed: isSubmitting ? null : onSubmit,
                      icon: isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Icon(canSubmit
                              ? Icons.send_rounded
                              : Icons.warning_amber_rounded,
                              size: 18),
                      label: Text(
                          isSubmitting
                              ? 'Submitting…'
                              : canSubmit
                                  ? 'Submit'
                                  : 'Complete Steps to Submit',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSubmit
                            ? AppColors.riderGreen
                            : AppColors.textTertiary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    )
                  : ElevatedButton(
                      onPressed: (() {
                        if (isAssigned && current == 0) return null;
                        if (current == 1 && ((uploadedCount + pendingCount) == 0 || !hasReport)) return null;
                        return onNext;
                      })(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.riderGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                        disabledBackgroundColor:
                            AppColors.riderGreen.withValues(alpha: 0.4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                              current == 0 ? 'Continue' : 'Next: Review',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED PREMIUM CARDS
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<Widget> children;
  const _PremiumSectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.children,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoTile(
      {required this.icon,
      required this.label,
      required this.value,
      this.valueColor});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 88,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600))),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: valueColor ?? AppColors.textPrimary))),
        ],
      ),
    );
  }
}
