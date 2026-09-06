// lib/presentation/features/head_manager/ci/screens/hm_ci_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';

final _ciDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, ciId) async {
  final ds = sl<CiRemoteDataSource>();
  return ds.getCiDetails(ciId);
});

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
    final ciAsync = ref.watch(_ciDetailProvider(widget.ciId));

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
      body: ciAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (ci) => ci == null
            ? const Center(child: Text('CI assignment not found'))
            : _buildContent(context, ci),
      ),
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
          LayoutBuilder(builder: (context, c) {
            final isNarrow = c.maxWidth < 860;
            final leftColumn = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildLenderCard(ci, model),
              const SizedBox(height: 16),
              _buildAssignmentCard(ci, model),
              if ((ci['report_summary'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                _buildReportCard(ci),
              ],
              if ((ci['ci_documents'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                _buildDocumentsCard(ci),
              ],
              if (status == 'approved' || status == 'rejected') ...[
                const SizedBox(height: 16),
                _buildReviewInfoCard(ci),
              ],
            ]);

            final rightRail = SizedBox(
              width: isNarrow ? double.infinity : 340,
              child: Column(children: [
                _buildStatusCard(ci, model, status),
                const SizedBox(height: 16),
                _buildProgressCard(ci, status),
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
    String completedLabel = '—';
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

  Widget _buildReportCard(Map<String, dynamic> ci) {
    return _SectionCard(
      title: 'CI Report',
      subtitle: 'Field investigation summary',
      child: Container(
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
          Expanded(child: Text(ci['report_summary'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.textPrimary))),
        ]),
      ),
    );
  }

  Widget _buildDocumentsCard(Map<String, dynamic> ci) {
    final docs = (ci['ci_documents'] as List?) ?? [];
    return _SectionCard(
      title: 'Evidence Photos (${docs.length})',
      subtitle: 'Captured during the field visit',
      child: GridView.builder(
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
    );
  }

  Widget _buildReviewInfoCard(Map<String, dynamic> ci) {
    final status = (ci['status'] as String? ?? '').toLowerCase();
    final isApproved = status == 'approved';
    final reviewer = ci['reviewer'] as Map<String, dynamic>?;
    final reviewerName = reviewer != null ? '${reviewer['first_name'] ?? ''} ${reviewer['last_name'] ?? ''}'.trim() : '—';
    final reviewedAt = ci['reviewed_at'] != null ? _dateFmt.format(parseManila(ci['reviewed_at'])!) : '—';
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
    final isOverdue = deadline != null && deadline.isOverdue && !['completed', 'approved'].contains(status);
    // Backend accepts straight to `in_progress` (no persistent `accepted`),
    // so derive acceptance from response_at for stale/cached rows where
    // status may still read `assigned`/`pending`.
    final hasAccepted = ci['response_at'] != null;
    var effective = status;
    if ((effective == 'assigned' || effective == 'pending' || effective.isEmpty) && hasAccepted) {
      effective = 'accepted';
    }
    final String msg;
    final Color msgColor;
    switch (effective) {
      case 'approved':
        msg = 'CI report approved — loan has been auto-approved.';
        msgColor = AppColors.success;
        break;
      case 'rejected':
        msg = 'CI report rejected — loan has been rejected.';
        msgColor = AppColors.error;
        break;
      case 'completed':
        msg = 'Report submitted — awaiting your decision.';
        msgColor = AppColors.warning;
        break;
      case 'in_progress':
        msg = 'Investigation is currently in progress.';
        msgColor = AppColors.lenderBlue;
        break;
      case 'accepted':
        msg = 'Rider accepted this assignment.';
        msgColor = AppColors.riderGreen;
        break;
      case 'declined':
        msg = 'Rider declined this assignment — please reassign.';
        msgColor = AppColors.error;
        break;
      case 'assigned':
      case 'pending':
        msg = 'Rider assigned — awaiting acceptance.';
        msgColor = AppColors.lenderBlue;
        break;
      default:
        if (hasAccepted) {
          msg = 'Rider accepted this assignment.';
          msgColor = AppColors.riderGreen;
        } else {
          msg = 'Rider assigned — awaiting acceptance.';
          msgColor = AppColors.lenderBlue;
        }
    }
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
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: msgColor.withValues(alpha: 0.08),
                border: Border.all(color: msgColor.withValues(alpha: 0.3)),
              ),
              child: Text(msg, style: TextStyle(color: msgColor, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
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
      child: Column(children: [
        for (int i = 0; i < steps.length; i++) ...[
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: steps[i].done
                    ? AppColors.riderGreen
                    : i == activeIndex
                        ? AppColors.lenderBlue
                        : AppColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(
                    color: steps[i].done
                        ? AppColors.riderGreen
                        : i == activeIndex
                            ? AppColors.lenderBlue
                            : AppColors.border),
              ),
              child: Icon(steps[i].icon,
                  size: 14,
                  color: steps[i].done || i == activeIndex ? Colors.white : AppColors.textTertiary),
            ),
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
      ]),
    );
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
  const _SectionCard({required this.title, this.subtitle = '', required this.child});

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(color: Color(0xFF5C6370), border: Border(bottom: BorderSide(color: AppColors.divider))),
          child: Row(children: [
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
              if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.white70)),
            ]),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: child),
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
