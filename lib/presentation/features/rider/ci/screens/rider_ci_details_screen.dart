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

import 'package:jireta_loans/core/extensions/date_extensions.dart';

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
  bool get _hasReport => true;
  // DEBUG FIX: upload must NOT succeed before Review Submit, so pending staged docs count toward canSubmit
  // Actual server upload happens atomically inside _submitFinal()
  // OPTIONAL ang report — hindi na ito nagba-block ng submit. Kapag blangko,
  // ang _performSubmit() ang nagpapadala ng "-" fallback dahil hindi
  // tinatanggap ng backend ang empty na report_summary.
  bool get _canSubmit =>
      _isAccepted && _effectiveDocsCount > 0 && !_isCompleted;

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
      title: 'Accept Assignment',
      message:
          'Are you sure you want to accept this Credit Investigation?',
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
      } else if (_isAssigned) {
        msg = 'You must accept the assignment first.';
      }
      if (!mounted) return;
      context.showSnackBarAsToast(SnackBar(
          content: Text(msg), backgroundColor: AppColors.error));
      // jump to the failing step (Step 2 is combined Upload & Report for 3-step wizard)
      if (_effectiveDocsCount == 0) {
        setState(() => _currentStep = 1);
      }
      return;
    }

    // The confirm dialog's Yes/Submit button shows a spinner while the upload
    // + submit run; Head Manager / Employee only see the report once this
    // completes successfully (status flips to completed).
    final confirmed = await showAsyncConfirmationDialog(
      context,
      title: 'Submit Report',
      message: 'Are you sure to submit this ci?',
      confirmLabel: 'Submit',
      confirmColor: AppColors.riderGreen,
      onConfirm: () => _performSubmit(),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(riderCiProvider.notifier).loadDetails(widget.ciId);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => const SuccessDialog(
        title: 'Report Submitted!',
        message: 'Your report and evidence have been submitted.',
      ),
    );
    if (!mounted) return;
    // stay on review step showing completed state
    setState(() => _currentStep = 2);
  }

  /// Runs inside the async confirmation dialog while the Yes button spins.
  /// Returns null on success, or an error message to show in the dialog.
  Future<String?> _performSubmit() async {
    // If there are pending local images not yet uploaded, upload first
    if (_pickedImages.isNotEmpty) {
      final okUp = await ref.read(riderCiProvider.notifier).uploadDocuments(
            ciId: widget.ciId,
            images: List.from(_pickedImages),
          );
      if (!okUp) {
        return 'Failed to upload pending photos. Please try again.';
      }
      if (mounted) setState(() => _pickedImages.clear());
      await ref.read(riderCiProvider.notifier).loadDetails(widget.ciId);
    }

    // Optional ang report — kapag blangko, "-" ang ipapadala dahil hindi
    // tinatanggap ng backend ang empty na report_summary.
    final summary = _reportCtrl.text.trim();
    final ok = await ref.read(riderCiProvider.notifier).submitReport(
          ciId: widget.ciId,
          reportSummary: summary.isEmpty ? '-' : summary,
        );
    if (!ok) {
      final err = ref.read(riderCiProvider).error;
      return (err == null || err.isEmpty)
          ? 'Failed to submit report. Please try again.'
          : 'Failed to submit report: $err';
    }
    return null;
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

    // Phone layout: the step actions are pinned to a fixed bottom bar instead
    // of scrolling with the content. Wide screens keep them inline.
    final isNarrow = MediaQuery.sizeOf(context).width < 900;

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
                      small: false,
                      // Green AppBar: semantic status colors would be
                      // unreadable here (e.g. "ASSIGNED" fell back to gray).
                      onDark: true)),
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
              : _isCompleted
                  ? _CompletedView(ci: ci)
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
                        // Force each step to FILL the area. The switcher's
                        // internal Stack centers shrink-wrapped children, which
                        // left a gap above the first card; a filling child
                        // starts flush under the pipeline header.
                        child: SizedBox.expand(
                          child: _buildStepContent(ci,
                              showInlineActions: !isNarrow),
                        ),
                      ),
                    ),
                    // Details step while unaccepted: Decline/Accept live in the
                    // bottom bar on phones (in the content on wide screens).
                    if (_isAssigned && _currentStep == 0 && isNarrow)
                      _DetailsActionBar(
                        onDecline: _handleDecline,
                        onAccept: _handleAccept,
                      ),
                    if (!(_isAssigned && _currentStep == 0))
                      _WizardBottomBar(
                        current: _currentStep,
                        isCompleted: _isCompleted,
                        isDeclined: _isDeclined,
                        canSubmit: _canSubmit,
                        isSubmitting: false,
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

  Widget _buildStepContent(CreditInvestigationModel ci,
      {bool showInlineActions = true}) {
    switch (_currentStep) {
      case 0:
        return _DetailsStep(
          key: const ValueKey(0),
          ci: ci,
          ciId: widget.ciId,
          onAccept: _handleAccept,
          onDecline: _handleDecline,
          showInlineActions: showInlineActions,
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
      // No bottom padding: the step content is flush with the pipeline header
      // (walang gap sa unang card).
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
              // Pipeline fill: green up to the active step, gray ahead.
              final toPrevFilled = i <= current || isCompleted;
              final toNextFilled = (i + 1) <= current || isCompleted;
              return Expanded(
                child: GestureDetector(
                  onTap: isLocked ? null : () => onTapStep(i),
                  child: Opacity(
                    opacity: isLocked ? 0.45 : 1,
                    child: Column(
                      children: [
                        // The circle is flanked by its two connector halves, so
                        // the pipeline actually joins the circles instead of a
                        // bar floating under the labels.
                        Row(
                          children: [
                            Expanded(
                              child: i == 0
                                  ? const SizedBox.shrink()
                                  : _StepConnector(filled: toPrevFilled),
                            ),
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
                            Expanded(
                              child: i == _steps.length - 1
                                  ? const SizedBox.shrink()
                                  : _StepConnector(filled: toNextFilled),
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
        ],
      ),
    );
  }
}

/// Half of the connector between two wizard circles. Two halves (from adjacent
/// columns) meet at the column boundary, so the line runs circle to circle.
class _StepConnector extends StatelessWidget {
  final bool filled;
  const _StepConnector({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2.5,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: filled ? AppColors.riderGreen : AppColors.border,
        borderRadius: BorderRadius.circular(2),
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

  /// False on phones: the actions are rendered in the fixed bottom bar instead
  /// (see `_DetailsActionBar`), so the inline row is skipped.
  final bool showInlineActions;
  const _DetailsStep(
      {super.key,
      required this.ci,
      required this.ciId,
      required this.onAccept,
      required this.onDecline,
      this.showInlineActions = true});

  @override
  Widget build(BuildContext context) {
    final isAssigned = ci.status == 'assigned';
    final isCompleted = ci.status == 'completed';
    return SingleChildScrollView(
      key: const ValueKey('details_scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      // No top padding: the cards sit directly under the pipeline header.
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Lender card — premium
          _DetailsSectionCard(
            title: 'Lender Information',
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
          _DetailsSectionCard(
            title: 'Assignment Details',
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
                          ci.deadline!.isOverdue &&
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
          // Inline actions — wide screens only (phones use the bottom bar).
          if (isAssigned && showInlineActions) ...[
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
              padding: EdgeInsets.zero,
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
          GestureDetector(
            onTap: onPickMulti,
            child: Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 2, strokeAlign: BorderSide.strokeAlignInside),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 40, color: AppColors.riderGreen),
                  SizedBox(height: 8),
                  Text('Tap to upload evidence', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  SizedBox(height: 4),
                  Text('Upload', style: TextStyle(fontSize: 12, color: AppColors.riderGreen, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
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
              padding: EdgeInsets.zero,
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
    final isCompleted = ci.status == 'completed';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Investigation Report',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
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
              decoration: const InputDecoration(
                hintText: 'Enter report (optional)',
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
    final isCompleted = ci.status == 'completed';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Upload section — CARD sa taas ng step. Dito nakalagay ang mga
          // upload ni rider (existing evidence + bagong piniling pending).
          _DetailsSectionCard(
            title: 'Upload Evidence *',
            icon: Icons.photo_camera_outlined,
            accent: AppColors.riderGreen,
            showDividers: false,
            children: [
              // Order inside the card: uploaded evidence photos, then the
              // newly picked (pending) photos, then the small text-only
              // "Upload" button at the bottom.
              if (uploaded.isNotEmpty) ...[
                GridView.builder(
                  shrinkWrap: true,
                  // Kailangan ang explicit zero padding — kapag null, idinadagdag
                  // ng Flutter ang MediaQuery insets (system nav bar) bilang
                  // SliverPadding, kaya may blangkong gap sa ilalim ng grid.
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8),
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
                                  color: AppColors.border,
                                  child: const Icon(
                                      Icons.broken_image_outlined,
                                      color: AppColors.textTertiary)))
                          : Container(
                              color: AppColors.border,
                              child: const Icon(Icons.photo_outlined,
                                  color: AppColors.textTertiary)),
                    );
                  },
                ),
                // Spacing lang kapag may Pending section sa ibaba — kung wala,
                // dikit agad ang Upload/Clear all row sa photos.
                if (hasPending) const SizedBox(height: 10),
              ],
              if (hasPending) ...[
                Text('Pending (${pickedImages.length})',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                GridView.builder(
                  shrinkWrap: true,
                  // Kailangan ang explicit zero padding — kapag null, idinadagdag
                  // ng Flutter ang MediaQuery insets (system nav bar) bilang
                  // SliverPadding, kaya may blangkong gap sa ilalim ng grid.
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8),
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
                                  color: AppColors.error,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close,
                                  size: 14, color: Colors.white)),
                        ),
                      ),
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
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
              // Small text-only Upload button (no big tap-to-upload box) na
              // dikit sa ilalim ng photos. Kapag may pending, naka-right align
              // ang [{Clear all} {Upload}] group — Upload ang nasa dulo.
              Row(
                children: [
                  if (hasPending) const Spacer(),
                  if (hasPending)
                    // Minimal padding + shrinkWrap para dikit (walang malaking
                    // gap) ang "Clear all" sa Upload button.
                    TextButton(
                      onPressed: onClearPicked,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Clear all'),
                    ),
                  OutlinedButton.icon(
                    onPressed: isCompleted ? null : onPickMulti,
                    icon: const Icon(Icons.upload_rounded, size: 16),
                    label: const Text('Upload'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.riderGreen,
                      side: const BorderSide(color: AppColors.riderGreen),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              if (uploaded.isEmpty && !hasPending) ...[
                const SizedBox(height: 8),
                const Text('Tap Upload to add evidence photos.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textTertiary)),
              ],
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── Report section (optional) ──
          const Text('Investigation Report (Optional)',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
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
              decoration: const InputDecoration(
                hintText: 'Enter report (optional)',
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
                // Pareho ng laman ng Details step: Lender Information +
                // Assignment Details (kasama ang Phone at Assigned By/At).
                _ReviewTile(
                    'Lender', ci.borrowerName.isEmpty ? 'N/A' : ci.borrowerName),
                _ReviewTile('Loan #', ci.loanNumber.isEmpty ? 'N/A' : ci.loanNumber),
                _ReviewTile('Address',
                    ci.borrowerAddress.isEmpty ? 'N/A' : ci.borrowerAddress),
                _ReviewTile(
                    'Phone', ci.borrowerPhone.isEmpty ? 'N/A' : ci.borrowerPhone),
                _ReviewTile('Assigned By',
                    ci.assignedByName.isEmpty ? 'N/A' : ci.assignedByName),
                _ReviewTile('Assigned At',
                    DateFormat('MMM d, yyyy • h:mm a').format(ci.assignedAt)),
                _ReviewTile(
                    'Deadline',
                    ci.deadline != null
                        ? DateFormat('MMM d, yyyy').format(ci.deadline!)
                        : 'No deadline',
                    valueColor: ci.deadline != null &&
                            ci.deadline!.isOverdue &&
                            !isCompleted
                        ? AppColors.error
                        : null),
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

          // Evidence Photos — show both uploaded and pending
          _ReviewCard(
            title: 'Evidence Photos (${uploaded.length + pickedImages.length})',
            icon: Icons.photo_library_rounded,
            color: AppColors.riderGreen,
            child: (uploaded.isEmpty && pickedImages.isEmpty)
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
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                    itemCount: (uploaded.length + pickedImages.length) > 6 ? 6 : (uploaded.length + pickedImages.length),
                    itemBuilder: (ctx, i) {
                      if (i < uploaded.length) {
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
                      }
                      final pendingIdx = i - uploaded.length;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: XFilePreview(file: pickedImages[pendingIdx]),
                      );
                    },
                  ),
          ),
          if ((uploaded.length + pickedImages.length) > 6)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('+ ${(uploaded.length + pickedImages.length) - 6} more photo(s)',
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
  final Color? valueColor;
  const _ReviewTile(this.label, this.value, {this.valueColor});
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
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: valueColor ?? AppColors.textPrimary))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPLETED VIEW — shows lender info only (no steps)
// ─────────────────────────────────────────────────────────────────────────────
class _CompletedView extends StatelessWidget {
  final CreditInvestigationModel ci;
  const _CompletedView({required this.ci});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
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
          const SizedBox(height: 16),
          _DetailsSectionCard(
            title: 'Lender Information',
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM BAR
// ─────────────────────────────────────────────────────────────────────────────
/// Pinned bottom bar with the Details step actions (Decline / Accept) used on
/// phones. Bare buttons on the page background — no white panel/border/shadow —
/// so the footer does not read as another card. The scroll area is a separate
/// `Expanded`, so the content never slides under these buttons.
class _DetailsActionBar extends StatelessWidget {
  final VoidCallback onDecline;
  final VoidCallback onAccept;
  const _DetailsActionBar(
      {required this.onDecline, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: SafeArea(
        top: false,
        child: Row(
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
      ),
    );
  }
}

class _WizardBottomBar extends StatelessWidget {
  final int current;
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
      // Flat footer — walang white box/border/shadow; nakapatong lang ang
      // button sa page background (same sa _DetailsActionBar).
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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

    // Flat footer — walang white box/border/shadow; nakapatong lang sa page bg.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
            // Pantay ang lapad ng Back at Next/Submit (dating flex: 2 ang Next).
            Expanded(
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
                        if (current == 1 &&
                            ((uploadedCount + pendingCount) == 0 ||
                                !hasReport)) {
                          return null;
                        }
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
                          Text(current == 0 ? 'Continue' : 'Next',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
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

class _DetailsSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<Widget> children;

  /// False = walang hairline separator sa pagitan ng children. Gamitin para sa
  /// custom content (tulad ng upload grid) na hindi label/value rows.
  final bool showDividers;

  const _DetailsSectionCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.children,
    this.showDividers = true,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: soft tinted icon chip + section name.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          // Rows are separated by hairlines so the values stay easy to scan.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (showDividers && i > 0)
                    const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  children[i],
                ],
              ],
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Small icon chip leads the row (the tile already receives an icon).
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: valueColor ?? AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
