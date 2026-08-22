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
import '../../../../shared/widgets/status_badge.dart';

final _collectionDetailProvider =
    FutureProvider.family<CollectionAssignmentModel?, String>(
  (ref, id) async {
    final ds = sl<CollectionRemoteDataSource>();
    final list = await ds.getCollectionList(limit: 1000);
    for (final c in list) {
      if (c.id == id) return c;
    }
    return null;
  },
);

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
        TextButton.icon(
          onPressed: () => context.go(RouteConstants.hmCollections),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back'),
        ),
        const SizedBox(width: 12),
      ],
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (col) => col == null
            ? const Center(child: Text('Collection not found'))
            : _buildContent(context, ref, col, fmt, dateFmt),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref,
      CollectionAssignmentModel col, NumberFormat fmt, DateFormat dateFmt) {
    final schedule = col.loanSchedule ?? {};
    final isOffice = col.collectionType == 'office';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(col, fmt, isOffice),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _InfoCard(
                  title: 'Assignment Info',
                  icon: Icons.assignment_outlined,
                  rows: [
                    _Row('Status', col.status),
                    _Row(
                        'Request Type',
                        isOffice
                            ? 'Pay at the Office'
                            : 'Rider Collection'),
                    // Lender identity — who requested/pays this collection.
                    _Row('Lender',
                        col.lenderName.isNotEmpty ? col.lenderName : 'N/A'),
                    if (col.lenderPhone.isNotEmpty)
                      _Row('Lender Phone', col.lenderPhone),
                    _Row(
                        isOffice ? 'Payment Location' : 'Assigned Rider',
                        isOffice
                            ? 'Office'
                            : col.riderName.isNotEmpty
                                ? col.riderName
                                : 'N/A'),
                    _Row(
                        'Assigned By',
                        col.assignedByName.isNotEmpty
                            ? col.assignedByName
                            : 'N/A'),
                    _Row(
                        'Schedule',
                        col.collectionSchedule != null
                            ? dateFmt.format(col.collectionSchedule!)
                            : 'N/A'),
                    _Row(
                        'Response At',
                        col.responseAt != null
                            ? dateFmt.format(col.responseAt!)
                            : 'N/A'),
                    _Row(
                        'Completed At',
                        col.completedAt != null
                            ? dateFmt.format(col.completedAt!)
                            : 'N/A'),
                    _Row('Notes', col.notes ?? 'None'),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _InfoCard(
                  title: 'Payment Info',
                  icon: Icons.payments_outlined,
                  rows: [
                    _Row(
                        'Amount Due',
                        schedule['amount_due'] != null
                            ? '₱${fmt.format((schedule['amount_due'] as num).toDouble())}'
                            : 'N/A'),
                    _Row(
                        'Amount Collected',
                        col.amountCollected != null
                            ? '₱${fmt.format(col.amountCollected!)}'
                            : 'N/A'),
                    _Row(
                        'Due Date',
                        schedule['due_date'] != null
                            ? DateFormat('MMM d, yyyy')
                                .format(DateTime.parse(schedule['due_date']))
                            : 'N/A'),
                    _Row('Period',
                        '${schedule['period_number'] ?? schedule['installment_number'] ?? 'N/A'}'),
                    _Row('Idempotency Key', col.idempotencyKey ?? 'N/A'),
                    // Proofs open on demand via the View button below.
                    if (col.proofPhoto != null ||
                        col.borrowerSignature != null ||
                        col.collectionPhoto != null) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => showCollectionProofDialog(context, [
                          if (col.proofPhoto != null)
                            CollectionProofItem(
                                label: 'Payment Proof', url: col.proofPhoto!),
                          if (col.borrowerSignature != null)
                            CollectionProofItem(
                                label: 'Borrower Signature',
                                url: col.borrowerSignature!),
                          if (col.collectionPhoto != null)
                            CollectionProofItem(
                                label: 'Scene Photo',
                                url: col.collectionPhoto!),
                        ]),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.deepNavy,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                        ),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('View Collection Proof'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (col.locationLat != null) ...[
            const SizedBox(height: 20),
            _buildLocationCard(col),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderCard(
      CollectionAssignmentModel col, NumberFormat fmt, bool isOffice) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.riderGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                  isOffice
                      ? Icons.storefront_outlined
                      : Icons.local_shipping_outlined,
                  color: AppColors.riderGreen,
                  size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    col.lenderName.isNotEmpty
                        ? col.lenderName
                        : isOffice
                            ? 'Office Payment Request'
                            : 'Collection Assignment',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${col.loanNumber.isNotEmpty ? col.loanNumber : ''}'
                    '${col.amountCollected != null ? '  ·  ₱${fmt.format(col.amountCollected!)} collected' : '  ·  Pending collection'}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
            StatusBadge(status: col.status),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(CollectionAssignmentModel col) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.location_on_outlined,
                    color: AppColors.deepNavy, size: 18),
                SizedBox(width: 8),
                Text('Collection Location',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(height: 20),
            Text(
              'Lat: ${col.locationLat?.toStringAsFixed(6)}, Lng: ${col.locationLng?.toStringAsFixed(6)}',
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> rows;
  const _InfoCard(
      {required this.title, required this.icon, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.deepNavy, size: 18),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(height: 20),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
