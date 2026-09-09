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

final _empCollectionDetailProvider =
    FutureProvider.family<CollectionAssignmentModel?, String>((ref, id) async {
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
    final async = ref.watch(_empCollectionDetailProvider(collectionId));
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final dateFmt = DateFormat('MMM d, yyyy h:mm a');

    return WebScaffold(
      title: 'Collection Details',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go(RouteConstants.empCollections),
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('Back', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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

  Widget _buildContent(
      BuildContext context, WidgetRef ref, CollectionAssignmentModel col, NumberFormat fmt, DateFormat dateFmt) {
    final schedule = col.loanSchedule ?? {};
    final isOffice = col.collectionType == 'office';
    final hasProof = col.proofPhoto != null || col.borrowerSignature != null || col.collectionPhoto != null;

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
                  _InfoRow('Loan Number', col.loanNumber.isNotEmpty ? col.loanNumber : '—'),
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
                  _InfoRow(isOffice ? 'Payment Location' : 'Assigned Rider', isOffice ? 'Office' : col.riderName.isNotEmpty ? col.riderName : 'Unassigned'),
                  _InfoRow('Assigned By', col.assignedByName.isNotEmpty ? col.assignedByName : 'N/A'),
                  _InfoRow('Schedule', col.collectionSchedule != null ? dateFmt.format(col.collectionSchedule!) : 'N/A'),
                  _InfoRow('Response At', col.responseAt != null ? dateFmt.format(col.responseAt!) : 'Pending'),
                  _InfoRow('Completed At', col.completedAt != null ? dateFmt.format(col.completedAt!) : '—'),
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
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.deepNavy, Color(0xFF1A2E4A)]),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 3))]),
                      child: ElevatedButton.icon(
                        onPressed: () => showCollectionProofDialog(context, [
                          if (col.proofPhoto != null) CollectionProofItem(label: 'Payment Proof', url: col.proofPhoto!),
                          if (col.borrowerSignature != null) CollectionProofItem(label: 'Lender Signature', url: col.borrowerSignature!),
                          if (col.collectionPhoto != null) CollectionProofItem(label: 'Scene Photo', url: col.collectionPhoto!),
                        ]),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
                    _InfoRow('Latitude', col.locationLat?.toStringAsFixed(6) ?? '—'),
                    _InfoRow('Longitude', col.locationLng?.toStringAsFixed(6) ?? '—'),
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
                      child: _buildStatusCard(col),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: const BoxDecoration(color: Color(0xFF5C6370), border: Border(bottom: BorderSide(color: AppColors.divider))),
                      child: const Row(children: [
                        SizedBox(width: 8),
                        Text('Progress', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildTimeline(col),
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
      _StatusRow('Completed', col.completedAt != null),
    ]);
  }

  Widget _buildTimeline(CollectionAssignmentModel col) {
    final steps = [
      ('Requested', col.collectionSchedule != null),
      ('Assigned', col.assignedByName.isNotEmpty),
      ('Accepted', col.responseAt != null),
      ('Completed', col.completedAt != null),
    ];
    return Column(children: [
      for (int i = 0; i < steps.length; i++) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: steps[i].$2 ? AppColors.riderGreen : AppColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: steps[i].$2 ? AppColors.riderGreen : AppColors.border),
              ),
              child: Icon(steps[i].$2 ? Icons.check_rounded : Icons.circle_outlined, size: 14, color: steps[i].$2 ? Colors.white : AppColors.textTertiary),
            ),
            if (i < steps.length - 1) Container(width: 2, height: 26, color: steps[i].$2 ? AppColors.riderGreen.withValues(alpha: 0.4) : AppColors.border),
          ]),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(steps[i].$1, style: TextStyle(fontSize: 12, fontWeight: steps[i].$2 ? FontWeight.w700 : FontWeight.w600, color: steps[i].$2 ? AppColors.textPrimary : AppColors.textSecondary)),
          ),
        ]),
      ],
    ]);
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
      case 'completed':
        return Icons.verified_rounded;
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
        return 'Rider is on the way';
      case 'completed':
        return 'Payment collected and verified';
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
      case 'completed':
        return AppColors.riderGreen;
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