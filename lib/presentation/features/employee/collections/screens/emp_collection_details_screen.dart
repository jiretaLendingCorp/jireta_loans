// lib/presentation/features/employee/collections/screens/emp_collection_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/details/collection_proof_viewer.dart';
import '../../../head_manager/collections/providers/hm_collection_provider.dart';
import '../../../head_manager/collections/widgets/assign_rider_collection_modal.dart';

final _collectionDetailProvider = FutureProvider.family<CollectionAssignmentModel?, String>((ref, id) async {
  final ds = sl<CollectionRemoteDataSource>();
  final list = await ds.getCollectionList(limit: 1000);
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
});

class EmpCollectionDetailsScreen extends ConsumerWidget {
  final String collectionId;
  const EmpCollectionDetailsScreen({super.key, required this.collectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_collectionDetailProvider(collectionId));
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final dateFmt = DateFormat('MMM d, yyyy h:mm a');

    return WebScaffold(
      title: 'Collection Details',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go(RouteConstants.empCollections),
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('Back', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
        const SizedBox(width: 12),
      ],
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
        data: (col) => col == null ? const Center(child: Text('Collection not found')) : _buildContent(context, ref, col, fmt, dateFmt),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, CollectionAssignmentModel col, NumberFormat fmt, DateFormat dateFmt) {
    final schedule = col.loanSchedule ?? {};
    final isOffice = col.collectionType == 'office';
    final hasProof = col.proofPhoto != null || col.borrowerSignature != null || col.collectionPhoto != null;
    // Business rule: `completed_at` = tapos na talaga (amount + proof na-submit).
    // Hindi na ito sine-set ng record step, kaya hindi na lumalabas ang
    // "Completed At" na timestamp sa isang `in_progress` na koleksyon.
    final isCompleted = col.status.toLowerCase() == 'completed';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, c) {
            final isNarrow = c.maxWidth < 860;
            final leftColumn = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PremiumSectionCard(
                title: 'Collection Overview',
                subtitle: isOffice ? 'Office walk-in payment' : 'Rider field collection',
                icon: Icons.request_page_rounded,
                accent: AppColors.riderGreen,
                child: Column(children: [
                  _InfoRow('Lender', col.lenderName.isNotEmpty ? col.lenderName : 'N/A'),
                  _InfoRow('Loan Number', col.loanNumber.isNotEmpty ? col.loanNumber : 'N/A'),
                  _InfoRow('Request Type', isOffice ? 'Pay at the Office' : 'Rider Collection'),
                  _InfoRow('Status', col.status),
                  _InfoRow('Amount Due', schedule['amount_due'] != null ? '₱${fmt.format((schedule['amount_due'] as num).toDouble())}' : 'N/A'),
                  _InfoRow('Amount Collected', col.amountCollected != null ? '₱${fmt.format(col.amountCollected!)}' : 'Not yet collected'),
                ]),
              ),
              const SizedBox(height: 16),
              _PremiumSectionCard(
                title: 'Assignment Info',
                subtitle: isOffice ? 'Office walk-in payment' : 'Rider field collection',
                icon: Icons.assignment_rounded,
                accent: AppColors.lenderBlue,
                child: Column(children: [
                  if (col.lenderPhone.isNotEmpty) _InfoRow('Lender Phone', col.lenderPhone),
                  _InfoRow(isOffice ? 'Payment Location' : 'Assigned Rider', isOffice ? 'Office' : col.riderName.isNotEmpty ? col.riderName : 'N/A'),
                  _InfoRow('Assigned By', col.assignedByName.isNotEmpty ? col.assignedByName : 'N/A'),
                  _InfoRow('Requested At', col.effectiveRequestedAt != null ? dateFmt.format(col.effectiveRequestedAt!) : 'N/A'),
                  _InfoRow('Assigned At', col.effectiveAssignedAt != null ? dateFmt.format(col.effectiveAssignedAt!) : 'N/A'),
                  _InfoRow('Schedule', col.collectionSchedule != null ? dateFmt.format(col.collectionSchedule!) : 'N/A'),
                  _InfoRow('Response At', col.responseAt != null ? dateFmt.format(col.responseAt!) : 'Pending'),
                  _InfoRow('Completed At',
                      isCompleted && col.completedAt != null ? dateFmt.format(col.completedAt!) : 'N/A'),
                  const Divider(height: 20),
                  _InfoRow('Notes', col.notes ?? 'None'),
                ]),
              ),
              if (col.locationLat != null) ...[
                const SizedBox(height: 16),
                _PremiumSectionCard(
                  title: 'Collection Location',
                  subtitle: 'GPS captured on completion',
                  icon: Icons.location_on_rounded,
                  accent: AppColors.riderGreen,
                  child: Column(children: [
                    _InfoRow('Latitude', col.locationLat?.toStringAsFixed(6) ?? 'N/A'),
                    _InfoRow('Longitude', col.locationLng?.toStringAsFixed(6) ?? 'N/A'),
                  ]),
                ),
              ],
            ]);

            // Collection Status — nasa TAAS na ng page (full width): dito agad
            // nakikita ang progreso ng koleksyon at ang approve/reject actions.
            final statusCard = Container(
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const BoxDecoration(color: Color(0xFF5C6370), border: Border(bottom: BorderSide(color: AppColors.divider))),
                  child: const Row(children: [
                    SizedBox(width: 8),
                    Text('Collection Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _buildStatusCard(col),
                    // Hindi na naka-stretch sa buong lapad ng page ang
                    // Approve/Reject ngayong nasa itaas na ang card.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _buildReviewActions(context, ref, col),
                    ),
                  ]),
                ),
              ]),
            );

            // Payment Info — inilipat sa dating pwesto ng Collection Status
            // (right rail), kasama ang View Collection Proof button.
            final paymentInfoCard = _PremiumSectionCard(
              title: 'Payment Info',
              subtitle: 'Reconciliation & proof',
              icon: Icons.payments_rounded,
              accent: AppColors.deepNavy,
              child: Column(children: [
                _InfoRow('Due Date', schedule['due_date'] != null ? DateFormat('MMM d, yyyy').format(DateTime.parse(schedule['due_date'])) : 'N/A'),
                _InfoRow('Period', '${schedule['period_number'] ?? schedule['installment_number'] ?? 'N/A'}'),
                _InfoRow('Idempotency Key', col.idempotencyKey ?? 'N/A'),
                if (hasProof) ...[
                  const SizedBox(height: 12),
                  // Compact na button — HINDI na buong lapad ng card. Sa
                  // desktop, kasya lang ito sa nilalaman at naka-left align:
                  // dati ay `width: double.infinity` kaya apat na salitang
                  // label ay humahaba sa buong lapad ng "Payment Info" card.
                  // Sa makitid na screen (< 860px) buong lapad pa rin — mas
                  // madaling tapikin gamit ang hinlalaki.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: isNarrow ? double.infinity : null,
                      child: Container(
                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.deepNavy, Color(0xFF1A2E4A)]), borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 3))]),
                        child: ElevatedButton.icon(
                          onPressed: () => showCollectionProofDialog(context, [
                            if (col.proofPhoto != null) CollectionProofItem(label: 'Payment Proof', url: col.proofPhoto!),
                            if (col.borrowerSignature != null) CollectionProofItem(label: 'Lender Signature', url: col.borrowerSignature!),
                            if (col.collectionPhoto != null) CollectionProofItem(label: 'Scene Photo', url: col.collectionPhoto!),
                          ]),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          icon: const Icon(Icons.visibility_rounded, size: 18, color: Colors.white),
                          label: const Text('View Collection Proof', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
            );

            final rightRail = SizedBox(
              width: isNarrow ? double.infinity : 340,
              child: Column(children: [paymentInfoCard]),
            );

            // Collection Status ang nasa ITAAS, tapos ang dalawang column
            // (left: overview/assignment, right: payment info) sa ilalim.
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              statusCard,
              const SizedBox(height: 16),
              if (isNarrow)
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [leftColumn, const SizedBox(height: 16), rightRail])
              else
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: leftColumn), const SizedBox(width: 16), rightRail]),
            ]);
          }),
        ],
      ),
    );
  }

  /// Progress pipeline ng koleksyon — ito ALONE ang laman ng card.
  ///
  /// Ang status icon + "Completed / Payment collected and approved" na header
  /// ay tinanggal (per request): ang pipeline na mismo ang nagpapakita ng
  /// progreso, at nasa Collection Overview pa rin ang hilaw na status row.
  ///
  /// HORIZONTAL ang mga stage (kaparehong wika ng "Workflow Progress" stepper
  /// ng CI details): dots na may connector sa pagitan, berde kapag tapos na,
  /// asul ang kasalukuyang stage, pula ang bigo, kulay-abuhin ang hindi pa.
  /// Nasa makitid na screen lang ang vertical na bersyon — doon kasi
  /// mag-c-cramp ang mga label kapag pinilit sa isang linya.
  Widget _buildStatusCard(CollectionAssignmentModel col) {
    final s = col.status.toLowerCase();
    final isRejected = s == 'rejected';
    final steps = <({String label, bool done, IconData icon})>[
      (label: 'Requested', done: col.collectionSchedule != null, icon: Icons.request_page_rounded),
      (label: 'Assigned', done: col.assignedByName.isNotEmpty, icon: Icons.assignment_ind_rounded),
      (label: 'Accepted', done: col.responseAt != null, icon: Icons.handshake_rounded),
      // Business rule: Completed lang kapag status == 'completed' (amount +
      // proof na-submit). Ang `completed_at` ay sine-set lang ng upload-proof
      // ngayon, pero status pa rin ang basehan dito — hindi timestamp.
      (
        label: 'Payment recorded',
        done: col.amountCollected != null ||
            s == 'in_progress' ||
            s == 'pending_approval' ||
            s == 'completed',
        icon: Icons.payments_rounded,
      ),
      (label: 'Submitted', done: s == 'pending_approval' || s == 'completed', icon: Icons.rate_review_rounded),
      // Business rule: `completed` lang kapag na-approve ng HM/Employee — dito
      // lang bumaba ang loan balance.
      (label: 'Approved', done: s == 'completed', icon: Icons.verified_rounded),
      // Hindi nakuha ang pera — pulang huling stage (hindi "tapos").
      if (isRejected)
        (label: 'Rejected', done: false, icon: Icons.close_rounded),
    ];
    final activeIndex = isRejected
        ? steps.length - 1
        : s == 'completed'
            ? 5
            : s == 'pending_approval'
                ? 4
                : (s == 'in_progress' || s == 'failed')
                    ? 3
                    : s == 'accepted'
                        ? 2
                        : (s == 'assigned' || s == 'declined')
                            ? 1
                            : 0;
    final failedIndex = isRejected ? steps.length - 1 : null;

    // Malawak na card ito (nasa taas na ng page) → horizontal pipeline para
    // puno ang lapad; makitid (mobile/tablet) → vertical.
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 720) {
        return _buildHorizontalPipeline(steps, activeIndex, failedIndex);
      }
      return _buildVerticalPipeline(steps, activeIndex, failedIndex);
    });
  }

  /// Vertical pipeline (makitid na screen): dot + label kada stage, may
  /// connector sa pagitan na nakatapat sa ilalim ng dot.
  Widget _buildVerticalPipeline(
      List<({String label, bool done, IconData icon})> steps,
      int activeIndex,
      int? failedIndex) {
    return Column(children: [
      for (int i = 0; i < steps.length; i++) ...[
        Row(children: [
          _pipelineDot(steps[i], i == activeIndex, i == failedIndex),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              steps[i].label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      i == activeIndex ? FontWeight.w800 : FontWeight.w600,
                  color: i == activeIndex
                      ? AppColors.deepNavy
                      : AppColors.textSecondary),
            ),
          ),
        ]),
        if (i < steps.length - 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SizedBox(
              width: 22,
              child: Center(
                child: Container(
                  width: 1.5,
                  height: 12,
                  color: steps[i].done
                      ? AppColors.riderGreen.withValues(alpha: 0.4)
                      : AppColors.border,
                ),
              ),
            ),
          ),
      ],
    ]);
  }

  /// Horizontal pipeline (malawak na card): naka-centro ang dot sa ibabaw ng
  /// label, may connector na linya sa pagitan ng mga stage.
  Widget _buildHorizontalPipeline(
      List<({String label, bool done, IconData icon})> steps,
      int activeIndex,
      int? failedIndex) {
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
                      : AppColors.border,
                ),
              ),
            ),
          SizedBox(
            width: 110,
            child: Column(children: [
              _pipelineDot(steps[i], i == activeIndex, i == failedIndex),
              const SizedBox(height: 6),
              Text(
                steps[i].label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        i == activeIndex ? FontWeight.w800 : FontWeight.w600,
                    color: i == activeIndex
                        ? AppColors.deepNavy
                        : AppColors.textSecondary),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  /// Isang dot ng pipeline: berde = tapos, asul = kasalukuyang stage, pula =
  /// bigong stage (rejected), abuhin = hindi pa.
  Widget _pipelineDot(({String label, bool done, IconData icon}) step,
      bool isActive, bool isFailed) {
    final dotColor = isFailed
        ? AppColors.error
        : step.done
            ? AppColors.riderGreen
            : isActive
                ? AppColors.lenderBlue
                : AppColors.surfaceVariant;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        border: Border.all(
            color: step.done || isActive || isFailed
                ? dotColor
                : AppColors.border),
      ),
      child: Icon(
        step.icon,
        size: 12,
        color: step.done || isActive || isFailed
            ? Colors.white
            : AppColors.textTertiary,
      ),
    );
  }

  /// Approve/Reject actions — lumalabas LANG habang `pending_approval`.
  /// Sa approve bumababa ang loan balance; sa reject, hindi.
  Widget _buildReviewActions(
      BuildContext context, WidgetRef ref, CollectionAssignmentModel col) {
    final s = col.status.toLowerCase();
    // Rejected = hindi nakuha ang pera → kailangang mag-assign muli ng rider.
    if (s == 'rejected') {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _reassignCollection(context, ref, col),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
            label: const Text('Reassign Rider'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepNavy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      );
    }
    if (s != 'pending_approval') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: const Row(children: [
            Icon(Icons.verified_user_outlined, size: 18, color: AppColors.warning),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Confirm that the rider actually received the cash before approving.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _rejectCollection(context, ref, col),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _approveCollection(context, ref, col),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Approve'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _approveCollection(
      BuildContext context, WidgetRef ref, CollectionAssignmentModel col) async {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final amount = col.amountCollected ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve Collection'),
        content: Text(
            'Confirm that ₱${fmt.format(amount)} was actually received from the lender. This will reduce the loan balance.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref.read(hmCollectionProvider.notifier).approveCollection(col.id);
    if (!context.mounted) return;
    ref.invalidate(_collectionDetailProvider(col.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Collection approved — loan balance updated' : 'Failed to approve collection'),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
  }

  Future<void> _reassignCollection(
      BuildContext context, WidgetRef ref, CollectionAssignmentModel col) async {
    final loanId = (col.loanSchedule?['loan']?['id'] as String?) ??
        (col.loanSchedule?['loan_id'] as String?) ??
        '';
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AssignRiderCollectionModal(
        loanScheduleId: col.loanScheduleId,
        loanId: loanId,
      ),
    );
    if (result != true || !context.mounted) return;
    ref.invalidate(_collectionDetailProvider(col.id));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Rider assigned successfully'),
      backgroundColor: AppColors.success,
    ));
  }

  Future<void> _rejectCollection(
      BuildContext context, WidgetRef ref, CollectionAssignmentModel col) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Collection'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'The cash was not received. The loan balance will NOT be reduced and a rider must be reassigned.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Reason (required)', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final reason = reasonCtrl.text.trim();
    if (reason.length < 3) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please provide a rejection reason'),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }
    final ok = await ref.read(hmCollectionProvider.notifier).rejectCollection(col.id, reason);
    if (!context.mounted) return;
    ref.invalidate(_collectionDetailProvider(col.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Collection rejected — reassign a rider' : 'Failed to reject collection'),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
  }

}

class _PremiumSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Widget child;

  const _PremiumSectionCard({required this.title, required this.subtitle, required this.icon, required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(color: Color(0xFF5C6370), border: Border(bottom: BorderSide(color: AppColors.divider))),
          child: Row(children: [
            Container(width: 24, height: 24, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)), child: Icon(icon, size: 14, color: Colors.white)),
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
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
      ]),
    );
  }
}