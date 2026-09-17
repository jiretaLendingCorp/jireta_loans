// lib/presentation/features/head_manager/ci/screens/hm_ci_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/providers/ci_detail_provider.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../providers/hm_ci_provider.dart';

class HmCiDetailsScreen extends ConsumerStatefulWidget {
  final String ciId;
  const HmCiDetailsScreen({super.key, required this.ciId});

  @override
  ConsumerState<HmCiDetailsScreen> createState() => _HmCiDetailsScreenState();
}

class _HmCiDetailsScreenState extends ConsumerState<HmCiDetailsScreen> {
  final _fmt = NumberFormat('#,##0.00', 'en_PH');
  final _dateFmt = DateFormat('MMM d, yyyy h:mm a');

  @override
  Widget build(BuildContext context) {
    final ciState = ref.watch(ciDetailProvider(widget.ciId));

    return WebScaffold(
      title: 'CI Assignment Details',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go(RouteConstants.hmCi),
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('Back to CI List',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
        ),
        const SizedBox(width: 12),
      ],
      body: ciState.isLoading && ciState.ci == null
          ? const Center(child: CircularProgressIndicator())
          : ciState.error != null && ciState.ci == null
              ? Center(
                  child: Text('Error: ${ciState.error}',
                      style: const TextStyle(color: AppColors.error)))
              : ciState.ci == null
                  ? const Center(child: Text('CI assignment not found'))
                  : _buildContent(context, ciState.ci!),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> ci) {
    final rawStatus = (ci['status'] as String? ?? '').trim();
    final status = rawStatus.toLowerCase();
    final model = CreditInvestigationModel.fromJson(ci);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Workflow Progress — FULL WIDTH sa pinaka-itaas ng page: dito agad
          // nakikita ng staff kung saang stage na ang assignment.
          _buildProgressCard(ci, status),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final isNarrow = c.maxWidth < 860;
            final leftColumn = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildLenderCard(ci, model),
              const SizedBox(height: 16),
              _buildAssignmentCard(ci, model),
              // Isang card na lang: CI Report + Evidence Photos.
              if ((ci['report_summary'] as String?)?.isNotEmpty == true ||
                  (ci['ci_documents'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                _buildReportEvidenceCard(ci),
              ],
              if (status == 'approved' || status == 'rejected') ...[
                const SizedBox(height: 16),
                _buildReviewInfoCard(ci),
              ],
            ]);

            // Nasa itaas na (full width) ang progress card — status card na
            // lang ang naiwan sa right rail.
            final rightRail = SizedBox(
              width: isNarrow ? double.infinity : 340,
              child: Column(children: [
                _buildStatusCard(ci, model, status),
              ]),
            );

            if (isNarrow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [leftColumn, const SizedBox(height: 16), rightRail]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: leftColumn),
              const SizedBox(width: 16),
              rightRail,
            ]);
          }),
        ],
      ),
    );
  }

  // ───────────────────────────── Left column cards ─────────────────────────────

  Widget _buildLenderCard(Map<String, dynamic> ci, CreditInvestigationModel model) {
    final addresses = ci['loans']?['lender_address'];
    final principal = ci['loans']?['principal_amount'];
    return _SectionCard(
      title: 'Lender Information',
      subtitle: 'Lender under investigation',
      child: Column(children: [
        _InfoRow('Name', model.borrowerName.isEmpty ? 'N/A' : model.borrowerName),
        _InfoRow('Phone', model.borrowerPhone.isEmpty ? 'N/A' : model.borrowerPhone),
        _InfoRow('Loan Amount', principal != null ? '₱${_fmt.format((principal as num).toDouble())}' : 'N/A', highlight: true),
        if (addresses is Map)
          _InfoRow('Primary Address', _formatAddress(Map<String, dynamic>.from(addresses))),
        _InfoRow('Deadline', ci['deadline'] != null ? DateFormat('MMM d, yyyy').format(parseManila(ci['deadline'])!) : 'N/A'),
      ]),
    );
  }

  DateTime? _parseCiDate(dynamic value) {
    if (value == null) return null;
    // response_at / completed_at / reviewed_at were historically written via
    // nowManilaISO() as Manila wall-time tagged UTC, while created_at is true
    // UTC. parseManila() (+8h) is correct for true UTC but double-shifts the
    // legacy wall-time values. Try parseManila first; if the result lies in
    // the future relative to Manila now, fall back to the raw wall time.
    final raw = DateTime.tryParse(value.toString());
    if (raw == null) return null;
    final viaManila = parseManila(value);
    if (viaManila != null && viaManila.isAfter(nowManila().add(const Duration(minutes: 5)))) {
      return raw.isUtc ? raw.toLocal() : raw;
    }
    return viaManila ?? raw;
  }

  Widget _buildAssignmentCard(Map<String, dynamic> ci, CreditInvestigationModel model) {
    final status = (ci['status'] as String? ?? '').trim().toLowerCase();
    final hasAccepted = ci['response_at'] != null;
    // Derive acceptance from response_at as well — backend moves
    // assigned -> in_progress on accept (no persistent `accepted` state),
    // so status alone can't be trusted for legacy/cached rows.
    String acceptedLabel;
    if (hasAccepted) {
      final dt = _parseCiDate(ci['response_at']);
      acceptedLabel = dt != null ? _dateFmt.format(dt) : ci['response_at'].toString();
    } else {
      acceptedLabel = status == 'declined' ? 'Declined' : 'Pending';
    }
    // Walang "—": kapag wala pang value ay 'N/A' ang nakalagay.
    String completedLabel = 'N/A';
    if (ci['completed_at'] != null) {
      final dt = _parseCiDate(ci['completed_at']);
      completedLabel = dt != null ? _dateFmt.format(dt) : ci['completed_at'].toString();
    }
    return _SectionCard(
      title: 'Assignment Details',
      subtitle: 'Workflow & ownership',
      child: Column(children: [
        _InfoRow('Status', (ci['status'] ?? 'N/A').toString().replaceAll('_', ' ')),
        _InfoRow('Assigned Rider', model.riderName.isEmpty ? 'Not Assigned' : model.riderName),
        _InfoRow('Assigned By', model.assignedByName.isEmpty ? 'N/A' : model.assignedByName),
        _InfoRow('Assigned At', ci['created_at'] != null ? _dateFmt.format(parseManila(ci['created_at'])!) : 'N/A'),
        _InfoRow('Accepted At', acceptedLabel),
        _InfoRow('Completed At', completedLabel),
        _InfoRow('CI Notes', (ci['investigation_notes'] as String?)?.isNotEmpty == true ? ci['investigation_notes'] as String : 'None'),
      ]),
    );
  }

  /// Pinagsamang card: CI Report + Evidence Photos. Dating magkahiwalay na
  /// card ito pero pareho naman ang konteksto (field visit), kaya isang card
  /// na lang para hindi hati ang atensyon ng nagre-review.
  Widget _buildReportEvidenceCard(Map<String, dynamic> ci) {
    final docs = (ci['ci_documents'] as List?) ?? [];
    final report = (ci['report_summary'] as String?) ?? '';
    return _SectionCard(
      title: docs.isEmpty
          ? 'CI Report'
          : 'CI Report & Evidence Photos (${docs.length})',
      subtitle: 'Field investigation summary',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (report.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('“', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textTertiary, height: 0.8)),
              const SizedBox(width: 8),
              Expanded(child: Text(report, style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.textPrimary))),
            ]),
          ),
        if (report.isNotEmpty && docs.isNotEmpty) const SizedBox(height: 16),
        if (docs.isNotEmpty) ...[
          const Text('Evidence Photos',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc = docs[i] as Map<String, dynamic>;
              return _DocumentThumbnail(doc: doc);
            },
          ),
        ],
      ]),
    );
  }

  Widget _buildReviewInfoCard(Map<String, dynamic> ci) {
    final status = (ci['status'] as String? ?? '').toLowerCase();
    final isApproved = status == 'approved';
    final reviewer = ci['reviewer'] as Map<String, dynamic>?;
    final reviewerName = reviewer != null ? '${reviewer['first_name'] ?? ''} ${reviewer['last_name'] ?? ''}'.trim() : 'N/A';
    final reviewedAt = ci['reviewed_at'] != null ? _dateFmt.format(parseManila(ci['reviewed_at'])!) : 'N/A';
    final notes = ci['review_notes'] as String? ?? (ci['review_decision'] as String? ?? '');
    return _SectionCard(
      title: isApproved ? 'CI Approved' : 'CI Rejected',
      subtitle: 'Reviewed by $reviewerName • $reviewedAt',
      child: notes.isEmpty
          ? Text(isApproved ? 'This investigation was approved.' : 'This investigation was rejected.',
              style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary))
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
              ),
              child: Text(notes, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary)),
            ),
    );
  }

  // ───────────────────────────── Right rail cards ─────────────────────────────

  Widget _buildStatusCard(Map<String, dynamic> ci, CreditInvestigationModel model, String status) {
    final deadline = parseManila(ci['deadline']);
    final isOverdue = deadline != null && deadline.isOverdue && !['completed', 'approved', 'rejected'].contains(status);
    final statusLabel = status.replaceAll('_', ' ').toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
            color: status == 'approved'
                ? AppColors.success.withValues(alpha: 0.3)
                : status == 'rejected'
                    ? AppColors.error.withValues(alpha: 0.3)
                    : AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(color: Color(0xFF5C6370)),
          child: Row(children: [
            const Expanded(
                child: Text('Assignment Status',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
            Text(statusLabel,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: status == 'rejected' ? AppColors.error : Colors.white)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoRow('CI Reference', 'CI-${model.id.substring(0, 8).toUpperCase()}', labelWidth: 120),
            _InfoRow('Loan Number', model.loanNumber.isEmpty ? 'N/A' : model.loanNumber, labelWidth: 120),
            if (deadline != null)
              _InfoRow('Deadline', DateFormat('MMM d, yyyy').format(deadline), labelWidth: 120, valueColor: isOverdue ? AppColors.error : null),
          ]),
        ),
      ]),
    );
  }

  Widget _buildProgressCard(Map<String, dynamic> ci, String status) {
    final isApproved = status == 'approved';
    final isRejected = status == 'rejected';
    final isCompletedPending = status == 'completed';
    final hasAccepted = ci['response_at'] != null;
    // Ang "kailangan pang i-approve/reject" indicator ay orange badge na
    // nakapatong sa 3-dots actions menu (tingnan ang _buildWorkflowActions),
    // kaya green pa rin ang icon ng tapos nang step dito sa stepper.
    final steps = <({String label, bool done, IconData icon})>[
      (label: 'Assigned', done: ci['created_at'] != null, icon: Icons.assignment_turned_in_rounded),
      (label: 'Accepted', done: hasAccepted || status == 'accepted' || status == 'in_progress' || isCompletedPending || isApproved || isRejected, icon: Icons.handshake_rounded),
      (label: 'In Progress', done: status == 'accepted' || status == 'in_progress' || isCompletedPending || isApproved || isRejected, icon: Icons.timelapse_rounded),
      (label: 'Submitted', done: ci['completed_at'] != null, icon: Icons.rate_review_rounded),
      (label: 'Approved', done: isApproved, icon: Icons.verified_rounded),
    ];
    final activeIndex = () {
      if (isApproved) return 4;
      if (isRejected) return 3;
      if (ci['completed_at'] != null) return 3;
      if (status == 'in_progress' || status == 'accepted') return 2;
      if (hasAccepted) return 1;
      return 0;
    }();

    return _SectionCard(
      title: 'Workflow Progress',
      subtitle: 'Assignment stages',
      // Compact na card — maliit ang header at laman para hindi kalat.
      compact: true,
      // 3-dot sa dulo ng header — dito na mismo i-approve/reject ang report.
      trailing: _buildWorkflowActions(ci, status),
      child: LayoutBuilder(builder: (context, c) {
        // Naka-wide ang card na ito (full width sa itaas ng page), kaya
        // HORIZONTAL stepper ang gamitin para puno ang buong lapad. Kapag
        // makitid (mobile/tablet), vertical pa rin para hindi mag-cramp ang
        // mga label.
        if (c.maxWidth >= 720) return _buildHorizontalSteps(steps, activeIndex);
        return _buildVerticalSteps(steps, activeIndex);
      }),
    );
  }

  Widget _buildVerticalSteps(
      List<({String label, bool done, IconData icon})> steps, int activeIndex) {
    return Column(children: [
      for (int i = 0; i < steps.length; i++) ...[
        Row(children: [
          _stepDot(steps[i], i == activeIndex),
          const SizedBox(width: 10),
          Expanded(
              child: Text(steps[i].label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == activeIndex ? FontWeight.w800 : FontWeight.w600,
                      color: i == activeIndex ? AppColors.deepNavy : AppColors.textSecondary))),
        ]),
        if (i < steps.length - 1)
          Padding(
            padding: const EdgeInsets.only(left: 13.5, top: 4, bottom: 4),
            child: Container(width: 1.5, height: 12, color: steps[i].done ? AppColors.riderGreen.withValues(alpha: 0.4) : AppColors.border),
          ),
      ],
    ]);
  }

  /// Horizontal stepper (wide card): naka-centro ang icon sa ibabaw ng label,
  /// may connector na linya sa pagitan ng mga stage.
  Widget _buildHorizontalSteps(
      List<({String label, bool done, IconData icon})> steps, int activeIndex) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                    height: 2,
                    color: steps[i - 1].done
                        ? AppColors.riderGreen.withValues(alpha: 0.4)
                        : AppColors.border),
              ),
            ),
          SizedBox(
            width: 96,
            child: Column(children: [
              _stepDot(steps[i], i == activeIndex),
              const SizedBox(height: 6),
              Text(steps[i].label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == activeIndex ? FontWeight.w800 : FontWeight.w600,
                      color: i == activeIndex ? AppColors.deepNavy : AppColors.textSecondary)),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _stepDot(({String label, bool done, IconData icon}) step, bool isActive) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: step.done
            ? AppColors.riderGreen
            : isActive
                ? AppColors.lenderBlue
                : AppColors.surfaceVariant,
        shape: BoxShape.circle,
        border: Border.all(
            color: step.done
                ? AppColors.riderGreen
                : isActive
                    ? AppColors.lenderBlue
                    : AppColors.border),
      ),
      child: Icon(step.icon,
          size: 12,
          color: step.done || isActive ? Colors.white : AppColors.textTertiary),
    );
  }

  // ─────────────────────────── Card header actions ───────────────────────────

  /// 3-dot menu sa dulong bahagi ng Workflow Progress card.
  ///
  /// Dito na mismo ginagawa ang CI report review (approve / reject) — hindi na
  /// kailangang bumalik sa CI list para hanapin ang row. Naka-grey ang dalawang
  /// action hangga't hindi pa naka-submit ang report (`completed`), at ang
  /// tooltip ang nagpapaliwanag nito.
  Widget _buildWorkflowActions(Map<String, dynamic> ci, String status) {
    final ciId = (ci['id'] ?? '').toString();
    final canReview = status == 'completed';
    return PopupMenuButton<String>(
      tooltip: canReview
          ? 'Actions'
          : 'Available once the rider submits the report',
      padding: EdgeInsets.zero,
      iconSize: 18,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      // Orange badge sa ibabaw ng 3-dots kapag naka-submit na ang report —
      // senyales na agad sa user na may approve/reject na dapat gawin.
      icon: SizedBox(
        width: 22,
        height: 22,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.more_vert_rounded, size: 18, color: Colors.white),
            if (canReview)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                    // Ring na kapareho ng header color para mukhang badge.
                    border: Border.all(
                        color: const Color(0xFF5C6370), width: 1.2),
                  ),
                ),
              ),
          ],
        ),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'approve',
          enabled: canReview,
          child: const Row(children: [
            Icon(Icons.verified_rounded, size: 16, color: AppColors.success),
            SizedBox(width: 10),
            Text('Approve'),
          ]),
        ),
        PopupMenuItem(
          value: 'reject',
          enabled: canReview,
          child: const Row(children: [
            Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
            SizedBox(width: 10),
            Text('Reject'),
          ]),
        ),
      ],
      onSelected: (value) {
        if (value == 'approve') _approveReport(ciId);
        if (value == 'reject') _rejectReport(ciId);
      },
    );
  }

  Future<void> _approveReport(String ciId) async {
    final ok = await ref.read(hmCiProvider.notifier).approveReport(ciId: ciId);
    if (!mounted) return;
    context.showSnackBarAsToast(SnackBar(
      content: Text(ok
          ? 'CI approved — loan is now approved'
          : 'Approve failed: ${ref.read(hmCiProvider).error ?? 'error'}'),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
    if (ok) _refreshAfterDecision();
  }

  Future<void> _rejectReport(String ciId) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject CI Report'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Provide reason (min 10 chars).',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'Rejection reason',
                  border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () {
                final r = reasonCtrl.text.trim();
                if (r.length < 10) {
                  context.showSnackBarAsToast(const SnackBar(
                      content: Text('Reason must be at least 10 characters')));
                  return;
                }
                Navigator.pop(context, r);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Reject', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    final ok =
        await ref.read(hmCiProvider.notifier).rejectReport(ciId: ciId, reason: reason);
    if (!mounted) return;
    context.showSnackBarAsToast(SnackBar(
      content: Text(ok
          ? 'CI report rejected — loan has been rejected'
          : 'Reject failed: ${ref.read(hmCiProvider).error ?? 'error'}'),
      backgroundColor: AppColors.error,
    ));
    if (ok) _refreshAfterDecision();
  }

  /// Status + progress + review cards sa details ay i-refresh pagkatapos ng
  /// desisyon (at pati na rin ang CI listahan sa likod nito).
  void _refreshAfterDecision() {
    ref.invalidate(ciDetailProvider(widget.ciId));
    ref.read(hmCiProvider.notifier).fetch(silent: true);
  }

  String _formatAddress(Map<String, dynamic> addr) {
    final parts = [addr['street'], addr['barangay'], addr['city'], addr['province']];
    return parts.where((p) => p != null && p.toString().isNotEmpty).join(', ');
  }
}

class _DocumentThumbnail extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _DocumentThumbnail({required this.doc});

  @override
  Widget build(BuildContext context) {
    final url = doc['file_url'] as String? ?? '';
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: AppColors.surfaceVariant, border: Border.all(color: AppColors.border)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Positioned.fill(
            child: url.isNotEmpty
                ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: AppColors.textTertiary))
                : const Center(child: Icon(Icons.photo_outlined, color: AppColors.textTertiary)),
          ),
          if ((doc['caption'] as String?)?.isNotEmpty == true)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black54], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                child: Text(doc['caption'] as String, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}

/// Square white card with the dark slate-grey (#5C6370) band header used across
/// the Lender Account Upgrade Details design.
class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  /// Opsyonal na widget sa dulong bahagi ng header — hal. ang 3-dot actions
  /// menu ng Workflow Progress card.
  final Widget? trailing;

  /// Mas maliit na card — masikip ang header at laman. Ginagamit ng
  /// Workflow Progress stepper.
  final bool compact;
  const _SectionCard(
      {required this.title,
      this.subtitle = '',
      required this.child,
      this.trailing,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 6 : 10),
          decoration: const BoxDecoration(color: Color(0xFF5C6370), border: Border(bottom: BorderSide(color: AppColors.divider))),
          child: Row(children: [
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    style: TextStyle(fontSize: compact ? 9 : 10, color: Colors.white70)),
            ]),
            if (trailing != null) ...[
              const Spacer(),
              trailing!,
            ],
          ]),
        ),
        Padding(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                : const EdgeInsets.all(16),
            child: child),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final double labelWidth;
  final bool highlight;
  final Color? valueColor;
  const _InfoRow(this.label, this.value,
      {this.labelWidth = 130, this.highlight = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: labelWidth,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? (highlight ? AppColors.deepNavy : AppColors.textPrimary)))),
      ]),
    );
  }
}
