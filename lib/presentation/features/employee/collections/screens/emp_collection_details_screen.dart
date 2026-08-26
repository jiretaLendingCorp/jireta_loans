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
import '../../../../shared/widgets/status_badge.dart';

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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPremiumHeader(col, fmt, isOffice),
          const SizedBox(height: 16),
          _buildTimeline(col),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final isNarrow = c.maxWidth < 860;
            if (isNarrow) {
              return Column(children: [
                _buildAssignmentCard(col, dateFmt, isOffice),
                const SizedBox(height: 16),
                _buildPaymentCard(col, schedule, fmt, context),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _buildAssignmentCard(col, dateFmt, isOffice)),
              const SizedBox(width: 16),
              Expanded(child: _buildPaymentCard(col, schedule, fmt, context)),
            ]);
          }),
          if (col.locationLat != null) ...[
            const SizedBox(height: 16),
            _buildLocationCard(col),
          ],
        ],
      ),
    );
  }

  Widget _buildPremiumHeader(CollectionAssignmentModel col, NumberFormat fmt, bool isOffice) {
    final accent = _accentForStatus(col.status);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: isOffice
                ? [const Color(0xFF0D1B2A), const Color(0xFF004D40)]
                : [const Color(0xFF0D1B2A), const Color(0xFF143D2B), const Color(0xFF1B5E20)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.7)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Icon(isOffice ? Icons.storefront_rounded : Icons.delivery_dining_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(col.lenderName.isNotEmpty ? col.lenderName : isOffice ? 'Office Payment Request' : 'Collection Assignment',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                  child: Text(isOffice ? 'OFFICE' : 'RIDER',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text(col.loanNumber.isNotEmpty ? col.loanNumber : '—',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                Text(col.amountCollected != null ? '₱${fmt.format(col.amountCollected!)} collected' : 'Pending collection',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ]),
          ),
          const SizedBox(width: 12),
          StatusBadge(status: col.status),
        ],
      ),
    );
  }

  Widget _buildTimeline(CollectionAssignmentModel col) {
    final steps = [
      ('Requested', col.collectionSchedule != null, Icons.request_page_rounded),
      ('Assigned', col.assignedByName.isNotEmpty, Icons.assignment_ind_rounded),
      ('Accepted', col.responseAt != null, Icons.handshake_rounded),
      ('Completed', col.completedAt != null, Icons.verified_rounded),
    ];
    int activeIdx = 0;
    if (col.completedAt != null) {
      activeIdx = 3;
    } else if (col.responseAt != null) {
      activeIdx = 2;
    } else if (col.assignedByName.isNotEmpty) {
      activeIdx = 1;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(
        children: steps.asMap().entries.map((e) {
          final idx = e.key;
          final isDone = e.value.$2;
          final isActive = idx == activeIdx;
          final isLast = idx == steps.length - 1;
          return Expanded(
            child: Row(children: [
              Column(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDone ? AppColors.riderGreen : isActive ? AppColors.lenderBlue : AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                    border: Border.all(color: isDone ? AppColors.riderGreen : isActive ? AppColors.lenderBlue : AppColors.border),
                  ),
                  child: Icon(e.value.$3, size: 16, color: isDone || isActive ? Colors.white : AppColors.textTertiary),
                ),
                const SizedBox(height: 6),
                Text(e.value.$1,
                    style:
                        TextStyle(fontSize: 11, fontWeight: isActive ? FontWeight.w800 : FontWeight.w600, color: isActive ? AppColors.deepNavy : AppColors.textSecondary)),
              ]),
              if (!isLast)
                Expanded(
                    child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                            color: isDone ? AppColors.riderGreen.withValues(alpha: 0.4) : AppColors.border,
                            borderRadius: BorderRadius.circular(2)))),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAssignmentCard(CollectionAssignmentModel col, DateFormat dateFmt, bool isOffice) {
    return _PremiumInfoCard(
      title: 'Assignment Info',
      subtitle: isOffice ? 'Office walk-in payment' : 'Rider field collection',
      icon: Icons.assignment_rounded,
      accent: AppColors.riderGreen,
      rows: [
        _Row('Status', col.status, icon: Icons.flag_rounded),
        _Row('Request Type', isOffice ? 'Pay at the Office' : 'Rider Collection',
            icon: isOffice ? Icons.storefront_rounded : Icons.delivery_dining_rounded),
        _Row('Lender', col.lenderName.isNotEmpty ? col.lenderName : 'N/A', icon: Icons.person_rounded),
        if (col.lenderPhone.isNotEmpty) _Row('Lender Phone', col.lenderPhone, icon: Icons.phone_rounded),
        _Row(isOffice ? 'Payment Location' : 'Assigned Rider', isOffice ? 'Office' : col.riderName.isNotEmpty ? col.riderName : 'Unassigned',
            icon: Icons.delivery_dining_rounded, highlight: !isOffice && col.riderName.isNotEmpty),
        _Row('Assigned By', col.assignedByName.isNotEmpty ? col.assignedByName : 'N/A', icon: Icons.admin_panel_settings_rounded),
        _Row('Schedule', col.collectionSchedule != null ? dateFmt.format(col.collectionSchedule!) : 'N/A', icon: Icons.event_rounded),
        _Row('Response At', col.responseAt != null ? dateFmt.format(col.responseAt!) : 'Pending', icon: Icons.schedule_rounded),
        _Row('Completed At', col.completedAt != null ? dateFmt.format(col.completedAt!) : '—', icon: Icons.verified_rounded),
        _Row('Notes', col.notes ?? 'None', icon: Icons.sticky_note_2_rounded),
      ],
    );
  }

  Widget _buildPaymentCard(CollectionAssignmentModel col, Map<String, dynamic> schedule, NumberFormat fmt, BuildContext context) {
    final hasProof = col.proofPhoto != null || col.borrowerSignature != null || col.collectionPhoto != null;
    return _PremiumInfoCard(
      title: 'Payment Info',
      subtitle: 'Reconciliation & proof',
      icon: Icons.payments_rounded,
      accent: AppColors.deepNavy,
      rows: [
        _Row('Amount Due', schedule['amount_due'] != null ? '₱${fmt.format((schedule['amount_due'] as num).toDouble())}' : 'N/A',
            icon: Icons.request_quote_rounded, highlight: true),
        _Row('Amount Collected', col.amountCollected != null ? '₱${fmt.format(col.amountCollected!)}' : 'Not yet collected',
            icon: Icons.savings_rounded, highlight: col.amountCollected != null),
        _Row('Due Date', schedule['due_date'] != null ? DateFormat('MMM d, yyyy').format(DateTime.parse(schedule['due_date'])) : 'N/A',
            icon: Icons.calendar_today_rounded),
        _Row('Period', '${schedule['period_number'] ?? schedule['installment_number'] ?? 'N/A'}', icon: Icons.tag_rounded),
        _Row('Idempotency Key', col.idempotencyKey ?? 'N/A', icon: Icons.fingerprint_rounded),
        if (hasProof) ...[
          const SizedBox(height: 8),
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
      ],
    );
  }

  Widget _buildLocationCard(CollectionAssignmentModel col) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.deepNavy.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: const Border(bottom: BorderSide(color: AppColors.divider))),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.deepNavy, Color(0xFF1A2E4A)]),
                    borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 18)),
            const SizedBox(width: 10),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Collection Location', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              Text('GPS captured on completion', style: TextStyle(fontSize: 11, color: AppColors.textSecondary))
            ]),
            const Spacer(),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.riderGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: const Text('GEOTAGGED',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.riderGreen))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: const Icon(Icons.my_location_rounded, size: 18, color: AppColors.deepNavy)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Lat: ${col.locationLat?.toStringAsFixed(6)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text('Lng: ${col.locationLng?.toStringAsFixed(6)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ])),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.map_rounded, size: 14, color: AppColors.deepNavy),
                      SizedBox(width: 6),
                      Text('Open Map', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))
                    ])),
              ]),
            ),
          ]),
        ),
      ]),
    );
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

class _PremiumInfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<Widget> rows;
  const _PremiumInfoCard(
      {required this.title, required this.subtitle, required this.icon, required this.accent, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              border: const Border(bottom: BorderSide(color: AppColors.divider)),
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
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))
            ]),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: Column(children: rows)),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool highlight;
  const _Row(this.label, this.value, {required this.icon, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 14, color: AppColors.textSecondary)),
        const SizedBox(width: 10),
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
        Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: highlight ? AppColors.deepNavy : AppColors.textPrimary))),
      ]),
    );
  }
}
