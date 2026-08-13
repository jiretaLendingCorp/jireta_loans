// lib/presentation/features/lender/collections/screens/lender_collection_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/document_viewer.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/lender_collection_provider.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
  MobileNavItem(
      icon: Icons.payment_outlined,
      activeIcon: Icons.payment,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile),
];

final _collectionDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final ds = ref.read(lenderCollectionProvider.notifier);
  return await ds.getDetail(id);
});

class LenderCollectionDetailsScreen extends ConsumerWidget {
  final String collectionId;
  const LenderCollectionDetailsScreen({super.key, required this.collectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_collectionDetailProvider(collectionId));

    return MobileScaffold(
      title: 'Collection Details',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: async.when(
        loading: () => const ShimmerLoader(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) => _buildBody(context, data),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'pending';
    final riderName = data['rider_name'] as String? ?? 'Assigned Rider';
    final riderId = data['rider_id'] as String? ?? '';
    final amountCollected =
        (data['amount_collected'] as num?)?.toDouble() ?? 0.0;
    final notes = data['notes'] as String?;
    final scheduledAt = data['collection_schedule'] as String?;
    final completedAt = data['completed_at'] as String?;
    final proofPhoto = data['proof_photo'] as String?;
    final borrowerSignature = data['borrower_signature'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusCard(
              status: status,
              riderName: riderName,
              riderId: riderId,
              scheduledAt: scheduledAt,
              completedAt: completedAt),
          const SizedBox(height: 16),
          _AmountCard(amountCollected: amountCollected, notes: notes),
          if (proofPhoto != null) ...[
            const SizedBox(height: 16),
            _ProofSection(title: 'Payment Proof', url: proofPhoto),
          ],
          if (borrowerSignature != null) ...[
            const SizedBox(height: 16),
            _ProofSection(title: 'Your Signature', url: borrowerSignature),
          ],
          if ((status == 'accepted' || status == 'pending') &&
              riderId.isNotEmpty) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push(
                    RouteConstants.lenderTrackRider.replaceAll(':id', riderId)),
                icon: const Icon(Icons.location_on),
                label: const Text('Track Rider Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.lenderBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String status, riderName, riderId;
  final String? scheduledAt, completedAt;
  const _StatusCard(
      {required this.status,
      required this.riderName,
      required this.riderId,
      this.scheduledAt,
      this.completedAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Collection Status',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.textPrimary)),
              const Spacer(),
              StatusBadge(status: status),
            ],
          ),
          const Divider(height: 20),
          _DetailRow(
              icon: Icons.delivery_dining, label: 'Rider', value: riderName),
          const SizedBox(height: 10),
          if (scheduledAt != null)
            _DetailRow(
                icon: Icons.schedule_outlined,
                label: 'Scheduled',
                value: DateTime.tryParse(scheduledAt!)?.toShortDate ?? '-'),
          if (completedAt != null) ...[
            const SizedBox(height: 10),
            _DetailRow(
                icon: Icons.check_circle_outline,
                label: 'Completed',
                value: DateTime.tryParse(completedAt!)?.toShortDate ?? '-'),
          ],
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  final double amountCollected;
  final String? notes;
  const _AmountCard({required this.amountCollected, this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payment Information',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.textPrimary)),
          const Divider(height: 20),
          _DetailRow(
              icon: Icons.attach_money,
              label: 'Amount Collected',
              value:
                  amountCollected > 0 ? amountCollected.toCurrency : 'Pending'),
          if (notes != null && notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailRow(
                icon: Icons.notes_outlined, label: 'Notes', value: notes!),
          ],
        ],
      ),
    );
  }
}

class _ProofSection extends StatelessWidget {
  final String title, url;
  const _ProofSection({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          DocumentViewer(url: url),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary))),
      ],
    );
  }
}
