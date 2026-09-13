// lib/presentation/features/head_manager/collections/screens/hm_collection_details_screen.dart
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
import '../providers/hm_collection_provider.dart';
import '../widgets/assign_rider_collection_modal.dart';

final _collectionDetailProvider = FutureProvider.family<CollectionAssignmentModel?, String>((ref, id) async {
  final ds = sl<CollectionRemoteDataSource>();
  final list = await ds.getCollectionList(limit: 1000);
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
});

class HmCollectionDetailsScreen extends ConsumerWidget {
  final String collectionId;
  const HmCollectionDetailsScreen({super.key, required this.collectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_collectionDetailProvider(collectionId));
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final dateFmt = DateFormat('MMM d, yyyy h:mm a');

    return WebScaffold(
      title: 'Collection Details',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go(RouteConstants.hmCollections),
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
                  const Divider(height: 20),
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
              const SizedBox(height: 16),
              _PremiumSectionCard(
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
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.deepNavy, Color(0xFF1A2E4A)]), borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 3))]),
                      child: ElevatedButton.icon(
                        onPressed: () => showCollectionProofDialog(context, [
                          if (col.proofPhoto != null) CollectionProofItem(label: 'Payment Proof', url: col.proofPhoto!),
                          if (col.borrowerSignature != null) CollectionProofItem(label: 'Lender Signature', url: col.borrowerSignature!),
                          if (col.collectionPhoto != null) CollectionProofItem(label: 'Scene Photo', url: col.collectionPhoto!),
                        ]),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        icon: const Icon(Icons.visibility_rounded, size: 18, color: Colors.white),
                        label: const Text('View Collection Proof', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
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

            final rightRail = SizedBox(
              width: isNarrow ? double.infinity : 340,
              child: Column(children: [
                Container(
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
                      child: Column(children: [
                        _buildStatusCard(col),
                        _buildReviewActions(context, ref, col),
                      ]),
                    ),
                  ]),
                ),
              ]),
            );

            if (isNarrow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [leftColumn, const SizedBox(height: 16), rightRail]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: leftColumn), const SizedBox(width: 16), rightRail]);
          }),
        ],
      ),
    );
  }

  Widget _buildStatusCard(CollectionAssignmentModel col) {
    final s = col.status.toLowerCase();
    final color = _accentForStatus(col.status);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)), child: Icon(_iconForStatus(s), size: 18, color: color)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_statusLabel(col.status), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          Text(_statusHint(s), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ])),
      ]),
      const SizedBox(height: 14),
      const Divider(height: 1, color: AppColors.border),
      const SizedBox(height: 12),
      _StatusRow('Requested', col.collectionSchedule != null),
      _StatusRow('Assigned', col.assignedByName.isNotEmpty),
      _StatusRow('Accepted', col.responseAt != null),
      // Business rule: Completed lang kapag status == 'completed' (amount +
      // proof na-submit). Ang `completed_at` ay sine-set lang ng upload-proof
      // ngayon, pero status pa rin ang basehan dito — hindi timestamp.
      _StatusRow('Collected (payment recorded)',
          col.amountCollected != null ||
              s == 'in_progress' ||
              s == 'pending_approval' ||
              s == 'completed'),
      _StatusRow('Submitted for approval', s == 'pending_approval' || s == 'completed'),
      // Business rule: `completed` lang kapag na-approve ng HM/Employee — dito
      // lang bumaba ang loan balance.
      _StatusRow('Approved & completed', s == 'completed'),
      if (s == 'rejected') const _StatusRow('Rejected (money not received)', false),
    ]);
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

  IconData _iconForStatus(String s) {
    switch (s) {
      case 'requested':
        return Icons.request_page_rounded;
      case 'assigned':
        return Icons.assignment_ind_rounded;
      case 'accepted':
        return Icons.handshake_rounded;
      case 'in_progress':
        return Icons.directions_bike_rounded;
      case 'pending_approval':
        return Icons.hourglass_top_rounded;
      case 'completed':
        return Icons.verified_rounded;
      case 'rejected':
      case 'failed':
      case 'declined':
        return Icons.cancel_rounded;
      default:
        return Icons.flag_rounded;
    }
  }

  String _statusLabel(String s) {
    switch (s.toLowerCase()) {
      case 'in_progress':
        return 'In Progress';
      default:
        return s.isEmpty ? 'Unknown' : s[0].toUpperCase() + s.substring(1);
    }
  }

  String _statusHint(String s) {
    switch (s) {
      case 'requested':
        return 'Lender request awaiting a rider';
      case 'assigned':
        return 'Rider assigned, awaiting acceptance';
      case 'accepted':
        return 'Rider accepted the collection';
      case 'in_progress':
        return 'Cash collected, awaiting proof upload';
      case 'pending_approval':
        return 'Rider submitted — awaiting approval';
      case 'completed':
        return 'Payment collected and approved';
      case 'rejected':
        return 'Rejected — money not received';
      case 'failed':
      case 'declined':
        return 'Collection was not completed';
      default:
        return '';
    }
  }

  Color _accentForStatus(String s) {
    switch (s.toLowerCase()) {
      case 'requested':
        return AppColors.warning;
      case 'assigned':
        return AppColors.lenderBlue;
      case 'accepted':
        return AppColors.riderGreen;
      case 'in_progress':
        return const Color(0xFFFFA000);
      case 'pending_approval':
        return AppColors.warning;
      case 'completed':
        return AppColors.riderGreen;
      case 'rejected':
      case 'failed':
      case 'declined':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
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

class _StatusRow extends StatelessWidget {
  final String label;
  final bool done;
  const _StatusRow(this.label, this.done);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 16, color: done ? AppColors.riderGreen : AppColors.textTertiary),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: done ? FontWeight.w700 : FontWeight.w600, color: done ? AppColors.textPrimary : AppColors.textSecondary)),
      ]),
    );
  }
}