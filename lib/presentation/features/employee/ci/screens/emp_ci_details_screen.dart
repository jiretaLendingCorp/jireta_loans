// lib/presentation/features/employee/ci/screens/emp_ci_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/emp_ci_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

final _ciDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, ciId) async {
  final ds = sl<CiRemoteDataSource>();
  return ds.getCiDetails(ciId);
});

final _availableRidersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final ds = sl<UserRemoteDataSource>();
  return ds.getAvailableRiders();
});

class EmpCiDetailsScreen extends ConsumerStatefulWidget {
  final String ciId;
  const EmpCiDetailsScreen({super.key, required this.ciId});

  @override
  ConsumerState<EmpCiDetailsScreen> createState() => _EmpCiDetailsScreenState();
}

class _EmpCiDetailsScreenState extends ConsumerState<EmpCiDetailsScreen> {
  final _fmt = NumberFormat('#,##0.00', 'en_PH');
  final _dateFmt = DateFormat('MMM d, yyyy h:mm a');

  @override
  Widget build(BuildContext context) {
    final ciAsync = ref.watch(_ciDetailProvider(widget.ciId));

    return WebScaffold(
      title: 'CI Assignment Details',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go(RouteConstants.empCi),
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
    final status = ci['status'] as String? ?? '';
    final model = CreditInvestigationModel.fromJson(ci);
    final isApproval = status == 'completed';
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPremiumHeader(model, status, ci),
                const SizedBox(height: 16),
                _buildTimeline(status, ci),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, c) {
                  final isNarrow = c.maxWidth < 820;
                  if (isNarrow) {
                    return Column(children: [
                      _buildLenderCard(ci, model),
                      const SizedBox(height: 16),
                      _buildAssignmentCard(ci, model),
                    ]);
                  }
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _buildLenderCard(ci, model)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildAssignmentCard(ci, model)),
                  ]);
                }),
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
                if (status == 'pending' || status == 'declined') ...[
                  const SizedBox(height: 16),
                  _buildAssignRiderSection(context, ci),
                ],
                if (isApproval) const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        if (isApproval) _buildApprovalBarOutside(context, ci),
      ],
    );
  }

  Widget _buildApprovalBarOutside(BuildContext context, Map<String, dynamic> ci) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: LayoutBuilder(builder: (cntx, c) {
        final isNarrow = c.maxWidth < 560;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.warning, Color(0xFFE65100)]),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.rate_review_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('CI Report — Awaiting Your Approval',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      Text('Review report & evidence, then approve or reject.',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _ApprovalButton(label: 'Reject', icon: Icons.close_rounded, color: AppColors.error, onTap: () => _showRejectDialog(context, ref, ci))),
                  const SizedBox(width: 10),
                  Expanded(child: _ApprovalButton(label: 'Approve', icon: Icons.check_rounded, color: AppColors.success, onTap: () => _showApproveDialog(context, ref, ci))),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.warning, Color(0xFFE65100)]),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.rate_review_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('CI Report — Awaiting Your Approval',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                Text('Review report & evidence, then approve or reject.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ]),
            ),
            const SizedBox(width: 12),
            _ApprovalButton(label: 'Reject', icon: Icons.close_rounded, color: AppColors.error, onTap: () => _showRejectDialog(context, ref, ci)),
            const SizedBox(width: 10),
            _ApprovalButton(label: 'Approve', icon: Icons.check_rounded, color: AppColors.success, onTap: () => _showApproveDialog(context, ref, ci)),
          ],
        );
      }),
    );
  }

  Widget _buildPremiumHeader(
      CreditInvestigationModel model, String status, Map<String, dynamic> ci) {
    final accent = _accentForStatus(status);
    final deadline =
        ci['deadline'] != null ? DateTime.tryParse(ci['deadline'].toString()) : null;
    final isOverdue = deadline != null &&
        deadline.isBefore(DateTime.now()) &&
        !['completed','approved'].contains(status);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.deepNavy,
          AppColors.deepNavy.withValues(alpha: 0.9),
          const Color(0xFF1E3A5F)
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.deepNavy.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient:
                  LinearGradient(colors: [accent, accent.withValues(alpha: 0.7)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: const Icon(Icons.search_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('CI-${model.id.substring(0, 8).toUpperCase()}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(width: 10),
                if (isOverdue)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('OVERDUE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                  ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(
                        'Loan: ${model.loanNumber.isEmpty ? 'N/A' : model.loanNumber}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                if (deadline != null)
                  Text('Due ${DateFormat('MMM d, yyyy').format(deadline)}',
                      style: TextStyle(
                          color: isOverdue
                              ? const Color(0xFFFF8A80)
                              : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
              ]),
            ]),
          ),
          const SizedBox(width: 12),
          StatusBadge(status: status),
        ],
      ),
    );
  }

  Widget _buildTimeline(String status, Map<String, dynamic> ci) {
    final isApproved = status == 'approved';
    final isRejected = status == 'rejected';
    final isCompletedPending = status == 'completed';
    final steps = [
      ('Assigned', ci['created_at'] != null, Icons.assignment_turned_in_rounded),
      ('Accepted', ci['response_at'] != null, Icons.handshake_rounded),
      ('In Progress', status == 'in_progress' || isCompletedPending || isApproved || isRejected, Icons.timelapse_rounded),
      ('Submitted', ci['completed_at'] != null, Icons.rate_review_rounded),
      ('Approved', isApproved, Icons.verified_rounded),
    ];
    final activeIndex = () {
      if (isApproved) return 4;
      if (isRejected) return 3;
      if (ci['completed_at'] != null) return 3;
      if (status == 'in_progress') return 2;
      if (ci['response_at'] != null) return 1;
      return 0;
    }();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(
        children: steps.asMap().entries.map((e) {
          final idx = e.key;
          final isDone = e.value.$2;
          final isActive = idx == activeIndex;
          final isLast = idx == steps.length - 1;
          return Expanded(
            child: Row(children: [
              Column(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.riderGreen
                        : isActive
                            ? AppColors.lenderBlue
                            : AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isDone
                            ? AppColors.riderGreen
                            : isActive
                                ? AppColors.lenderBlue
                                : AppColors.border),
                  ),
                  child: Icon(e.value.$3,
                      size: 16,
                      color: isDone || isActive ? Colors.white : AppColors.textTertiary),
                ),
                const SizedBox(height: 6),
                Text(e.value.$1,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                        color: isActive ? AppColors.deepNavy : AppColors.textSecondary)),
              ]),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isDone
                          ? AppColors.riderGreen.withValues(alpha: 0.4)
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLenderCard(Map<String, dynamic> ci, CreditInvestigationModel model) {
    final addresses = ci['loans']?['lender_address'];
    final principal = ci['loans']?['principal_amount'];
    return _PremiumInfoCard(
      title: 'Lender Information',
      subtitle: 'Lender under investigation',
      icon: Icons.person_rounded,
      accent: AppColors.lenderBlue,
      children: [
        _InfoRow('Name', model.borrowerName.isEmpty ? 'N/A' : model.borrowerName,
            icon: Icons.badge_outlined),
        _InfoRow('Phone', model.borrowerPhone.isEmpty ? 'N/A' : model.borrowerPhone,
            icon: Icons.phone_outlined),
        _InfoRow(
            'Loan Amount',
            principal != null
                ? '₱${_fmt.format((principal as num).toDouble())}'
                : 'N/A',
            icon: Icons.payments_outlined,
            highlight: true),
        if (addresses is Map)
          _InfoRow('Primary Address',
              _formatAddress(Map<String, dynamic>.from(addresses)),
              icon: Icons.location_on_outlined),
        _InfoRow('CI Notes', ci['investigation_notes'] ?? 'None',
            icon: Icons.sticky_note_2_outlined),
        _InfoRow(
            'Deadline',
            ci['deadline'] != null
                ? DateFormat('MMM d, yyyy').format(DateTime.parse(ci['deadline']))
                : 'N/A',
            icon: Icons.event_outlined),
      ],
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> ci, CreditInvestigationModel model) {
    return _PremiumInfoCard(
      title: 'Assignment Details',
      subtitle: 'Workflow & ownership',
      icon: Icons.assignment_rounded,
      accent: AppColors.deepNavy,
      children: [
        _InfoRow('Status', (ci['status'] ?? 'N/A').toString().replaceAll('_', ' '),
            icon: Icons.flag_outlined),
        _InfoRow('Assigned Rider',
            model.riderName.isEmpty ? 'Not Assigned' : model.riderName,
            icon: Icons.delivery_dining_rounded),
        _InfoRow('Assigned By',
            model.assignedByName.isEmpty ? 'N/A' : model.assignedByName,
            icon: Icons.admin_panel_settings_outlined),
        _InfoRow(
            'Assigned At',
            ci['created_at'] != null
                ? _dateFmt.format(DateTime.parse(ci['created_at']))
                : 'N/A',
            icon: Icons.schedule_rounded),
        _InfoRow(
            'Accepted At',
            ci['response_at'] != null
                ? _dateFmt.format(DateTime.parse(ci['response_at']))
                : 'Pending',
            icon: Icons.check_circle_outline_rounded),
        _InfoRow(
            'Completed At',
            ci['completed_at'] != null
                ? _dateFmt.format(DateTime.parse(ci['completed_at']))
                : '—',
            icon: Icons.verified_outlined),
      ],
    );
  }

  Widget _buildReportCard(Map<String, dynamic> ci) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider))),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xFF00838F), Color(0xFF006064)]),
                    borderRadius: BorderRadius.all(Radius.circular(9))),
                child: const Icon(Icons.article_rounded, color: Colors.white, size: 18)),
            const SizedBox(width: 10),
            const Text('Investigation Report',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('FIELD REPORT',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.6))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('“',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textTertiary,
                      height: 0.8)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(ci['report_summary'] as String? ?? '',
                      style: const TextStyle(
                          fontSize: 14, height: 1.6, color: AppColors.textPrimary))),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildDocumentsCard(Map<String, dynamic> ci) {
    final docs = (ci['ci_documents'] as List?) ?? [];
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: AppColors.deepNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.photo_library_rounded,
                    color: AppColors.deepNavy, size: 18)),
            const SizedBox(width: 10),
            Text('Evidence Photos (${docs.length})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('${docs.length} files',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
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
        ),
      ]),
    );
  }

  Widget _buildAssignRiderSection(BuildContext context, Map<String, dynamic> ci) {
    final ridersAsync = ref.watch(_availableRidersProvider);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.gold, AppColors.goldDark]),
                    borderRadius: BorderRadius.all(Radius.circular(9))),
                child: const Icon(Icons.assignment_ind_rounded,
                    color: Colors.white, size: 18)),
            const SizedBox(width: 10),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Assign Rider for CI',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              Text('Choose a field rider and set investigation timeline',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ridersAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not load riders: $e'),
            data: (riders) => _AssignRiderForm(
                ciId: widget.ciId,
                loanId: ci['loan_id'] as String? ?? '',
                riders: riders,
                onAssigned: () => ref.invalidate(_ciDetailProvider(widget.ciId))),
          ),
        ),
      ]),
    );
  }

  String _formatAddress(Map<String, dynamic> addr) {
    final parts = [addr['street'], addr['barangay'], addr['city'], addr['province']];
    return parts.where((p) => p != null && p.toString().isNotEmpty).join(', ');
  }

  Color _accentForStatus(String s) {
    switch (s.toLowerCase()) {
      case 'assigned':
        return AppColors.lenderBlue;
      case 'accepted':
        return AppColors.riderGreen;
      case 'in_progress':
        return AppColors.warning;
      case 'completed':
        return AppColors.warning;
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      case 'declined':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildReviewInfoCard(Map<String, dynamic> ci) {
    final status = (ci['status'] as String? ?? '').toLowerCase();
    final isApproved = status == 'approved';
    final reviewer = ci['reviewer'] as Map<String, dynamic>?;
    final reviewerName = reviewer != null ? '${reviewer['first_name'] ?? ''} ${reviewer['last_name'] ?? ''}'.trim() : '—';
    final reviewedAt = ci['reviewed_at'] != null ? DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(ci['reviewed_at'].toString())) : '—';
    final notes = ci['review_notes'] as String? ?? (ci['review_decision'] as String? ?? '');
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: isApproved ? AppColors.success.withValues(alpha: 0.35) : AppColors.error.withValues(alpha: 0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: isApproved ? AppColors.success.withValues(alpha: 0.08) : AppColors.error.withValues(alpha: 0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
          child: Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: isApproved ? AppColors.success : AppColors.error, borderRadius: BorderRadius.circular(9)), child: Icon(isApproved ? Icons.verified_rounded : Icons.block_rounded, color: Colors.white, size: 18)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isApproved ? 'CI Approved' : 'CI Rejected', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isApproved ? AppColors.success : AppColors.error)),
              Text('Reviewed by $reviewerName • $reviewedAt', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ]),
        ),
        if (notes.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border.withValues(alpha: 0.6))), child: Text(notes, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary)))),
      ]),
    );
  }

  void _showApproveDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> ci) {
    final notesCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve CI Report'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Are you sure you want to approve this investigation? Lender will be able to choose disbursement method after your approval and the loan can then be approved.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Optional review notes', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () async {
              Navigator.pop(context);
              final ok = await ref.read(empCiProvider.notifier).approveReport(ciId: ci['id'] as String, notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim());
              if (ok && context.mounted) {
                context.showSnackBarAsToast(const SnackBar(content: Text('CI approved — loan ready for final approval'), backgroundColor: AppColors.success));
                ref.invalidate(_ciDetailProvider(ci['id'] as String));
              } else if (context.mounted) {
                context.showSnackBarAsToast(SnackBar(content: Text('Failed: ${ref.read(empCiProvider).error ?? 'error'}'), backgroundColor: AppColors.error));
              }
            },
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> ci) {
    final reasonCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject CI Report'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Provide a reason for rejection (min 10 chars). Loan will return to review and a new CI can be assigned.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(controller: reasonCtrl, maxLines: 4, decoration: const InputDecoration(hintText: 'Rejection reason', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.length < 10) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reason must be at least 10 characters')));
                return;
              }
              Navigator.pop(context);
              final ok = await ref.read(empCiProvider.notifier).rejectReport(ciId: ci['id'] as String, reason: reason);
              if (ok && context.mounted) {
                context.showSnackBarAsToast(const SnackBar(content: Text('CI rejected — loan returned to review'), backgroundColor: AppColors.error));
                ref.invalidate(_ciDetailProvider(ci['id'] as String));
              } else if (context.mounted) {
                context.showSnackBarAsToast(SnackBar(content: Text('Failed: ${ref.read(empCiProvider).error ?? 'error'}'), backgroundColor: AppColors.error));
              }
            },
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _AssignRiderForm extends ConsumerStatefulWidget {
  final String ciId;
  final String loanId;
  final List<Map<String, dynamic>> riders;
  final VoidCallback onAssigned;

  const _AssignRiderForm(
      {required this.ciId,
      required this.loanId,
      required this.riders,
      required this.onAssigned});

  @override
  ConsumerState<_AssignRiderForm> createState() => _AssignRiderFormState();
}

class _AssignRiderFormState extends ConsumerState<_AssignRiderForm> {
  String? _selectedRiderId;
  final _notesCtrl = TextEditingController();
  DateTime? _deadline;
  bool _loading = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Select Rider', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: _selectedRiderId,
        decoration: InputDecoration(
          hintText: 'Choose available rider',
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.deepNavy, width: 1.4)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        items: widget.riders
            .map((r) => DropdownMenuItem<String>(
                value: r['id'] as String,
                child: Text('${r['first_name']} ${r['last_name']}',
                    style: const TextStyle(fontSize: 13))))
            .toList(),
        onChanged: (v) => setState(() => _selectedRiderId = v),
      ),
      const SizedBox(height: 14),
      const Text('Investigation Notes',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      TextFormField(
        controller: _notesCtrl,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: 'Add instructions for the field rider…',
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.deepNavy, width: 1.4)),
        ),
      ),
      const SizedBox(height: 14),
      const Text('Deadline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      InkWell(
        onTap: () async {
          final d = await showDatePicker(
              context: context,
              initialDate: DateTime.now().add(const Duration(days: 3)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 30)));
          if (d != null) setState(() => _deadline = d);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border)),
                child: const Icon(Icons.calendar_today_rounded,
                    size: 16, color: AppColors.deepNavy)),
            const SizedBox(width: 10),
            Text(_deadline != null ? DateFormat('MMM d, yyyy').format(_deadline!) : 'Select Deadline',
                style: TextStyle(
                    color: _deadline != null ? AppColors.textPrimary : AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            const Spacer(),
            const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textTertiary),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: Container(
          decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.deepNavy, Color(0xFF1A2E4A)]),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: AppColors.deepNavy.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ]),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: _selectedRiderId == null || _loading ? null : _assign,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
            label: Text(_loading ? 'Assigning…' : 'Assign Rider',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    ]);
  }

  Future<void> _assign() async {
    if (_selectedRiderId == null) return;
    setState(() => _loading = true);
    try {
      final ds = sl<CiRemoteDataSource>();
      await ds.assignCi(
          loanId: widget.loanId,
          riderId: _selectedRiderId!,
          investigationNotes: _notesCtrl.text.trim(),
          deadline: _deadline?.toIso8601String());
      if (mounted) {
        context.showSnackBarAsToast(const SnackBar(
            content: Text('Rider assigned successfully'), backgroundColor: AppColors.success));
        widget.onAssigned();
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBarAsToast(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _DocumentThumbnail extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _DocumentThumbnail({required this.doc});

  @override
  Widget build(BuildContext context) {
    final url = doc['file_url'] as String? ?? '';
    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.surfaceVariant,
          border: Border.all(color: AppColors.border)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Positioned.fill(
            child: url.isNotEmpty
                ? Image.network(url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_rounded, color: AppColors.textTertiary))
                : const Center(child: Icon(Icons.photo_outlined, color: AppColors.textTertiary)),
          ),
          if ((doc['caption'] as String?)?.isNotEmpty == true)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black54],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter)),
                child: Text(doc['caption'] as String,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}

class _PremiumInfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<Widget> children;
  const _PremiumInfoCard(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.accent,
      required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              border: const Border(bottom: BorderSide(color: AppColors.divider)),
              color: accent.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: Colors.white, size: 18)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: Column(children: children)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool highlight;
  const _InfoRow(this.label, this.value, {required this.icon, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 14, color: AppColors.textSecondary)),
        const SizedBox(width: 10),
        SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: highlight ? AppColors.deepNavy : AppColors.textPrimary))),
      ]),
    );
  }
}

class _ApprovalButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ApprovalButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
