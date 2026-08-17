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
import '../../../../shared/widgets/status_badge.dart';
import '../widgets/assign_rider_collection_modal.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

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
    final rider = col.rider ?? {};
    final assignedBy = col.assignedByUser ?? {};
    final isOffice = col.collectionType == 'office';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(col, fmt, isOffice),
          if (col.status == 'requested' && !isOffice) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _assignRider(context, ref, col),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.riderGreen,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: const Text('Assign Rider'),
              ),
            ),
          ],
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
                    _Row(
                        isOffice ? 'Payment Location' : 'Assigned Rider',
                        isOffice
                            ? 'Office'
                            : rider.isNotEmpty
                                ? '${rider['first_name']} ${rider['last_name']}'
                                : 'N/A'),
                    _Row(
                        'Assigned By',
                        assignedBy.isNotEmpty
                            ? '${assignedBy['first_name']} ${assignedBy['last_name']}'
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
                  ],
                ),
              ),
            ],
          ),
          if (col.proofPhoto != null ||
              col.borrowerSignature != null ||
              col.collectionPhoto != null) ...[
            const SizedBox(height: 20),
            _buildProofSection(col),
          ],
          if (col.locationLat != null) ...[
            const SizedBox(height: 20),
            _buildLocationCard(col),
          ],
        ],
      ),
    );
  }

  Future<void> _assignRider(
      BuildContext context, WidgetRef ref, CollectionAssignmentModel col) async {
    final loanId =
        (col.loanSchedule?['loan']?['id'] as String?) ?? '';
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AssignRiderCollectionModal(
        loanScheduleId: col.loanScheduleId,
        loanId: loanId,
        assignmentId: col.id,
      ),
    );
    if (result == true && context.mounted) {
      ref.invalidate(_collectionDetailProvider(col.id));
      context.showSnackBarAsToast(
        const SnackBar(content: Text('Rider assigned successfully')),
      );
    }
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
                    isOffice
                        ? 'Office Payment Request'
                        : 'Collection Assignment',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    col.amountCollected != null
                        ? '₱${fmt.format(col.amountCollected!)} Collected'
                        : 'Pending Collection',
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

  Widget _buildProofSection(CollectionAssignmentModel col) {
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
                Icon(Icons.photo_library_outlined,
                    color: AppColors.deepNavy, size: 18),
                SizedBox(width: 8),
                Text('Collection Proof',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                if (col.proofPhoto != null)
                  _ProofImage(url: col.proofPhoto!, label: 'Payment Proof'),
                if (col.borrowerSignature != null)
                  _ProofImage(url: col.borrowerSignature!, label: 'Signature'),
                if (col.collectionPhoto != null)
                  _ProofImage(url: col.collectionPhoto!, label: 'Scene Photo'),
              ],
            ),
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

class _ProofImage extends StatelessWidget {
  final String url;
  final String label;
  const _ProofImage({required this.url, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 140,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
              color: AppColors.surfaceVariant,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textTertiary)),
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_Row> rows;
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
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 130,
                          child: Text(r.label,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary))),
                      Expanded(
                          child: Text(r.value,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _Row {
  final String label;
  final String value;
  const _Row(this.label, this.value);
}
