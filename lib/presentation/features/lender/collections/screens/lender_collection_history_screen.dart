// lib/presentation/features/lender/collections/screens/lender_collection_history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
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

class LenderCollectionHistoryScreen extends ConsumerStatefulWidget {
  const LenderCollectionHistoryScreen({super.key});

  @override
  ConsumerState<LenderCollectionHistoryScreen> createState() => _State();
}

class _State extends ConsumerState<LenderCollectionHistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(lenderCollectionProvider.notifier).loadList());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderCollectionProvider);

    return MobileScaffold(
      title: 'Collection History',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      body: state.isLoading
          ? const ShimmerLoader()
          : state.hasError
              ? Center(child: Text('Failed to load: ${state.error}'))
              : RefreshIndicator(
                  color: AppColors.lenderBlue,
                  onRefresh: () =>
                      ref.read(lenderCollectionProvider.notifier).loadList(),
                  child: _buildBody(state.value ?? {'items': [], 'total': 0}),
                ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final items = (data['items'] as List?) ?? [];
    if (items.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.local_shipping_outlined,
        title: 'No Collections Yet',
        subtitle:
            'Collection visits will appear here once a rider is assigned to collect your payment.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (ctx, i) =>
          _CollectionCard(item: items[i] as Map<String, dynamic>),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _CollectionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String? ?? 'pending';
    final riderName = item['rider_name'] as String? ?? 'Assigned Rider';
    final amountCollected =
        (item['amount_collected'] as num?)?.toDouble() ?? 0.0;
    final scheduledAt = item['collection_schedule'] as String?;
    final completedAt = item['completed_at'] as String?;
    final collectionId = item['id'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: InkWell(
        onTap: () =>
            context.push('${RouteConstants.lenderCollections}/$collectionId'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.lenderBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delivery_dining,
                        color: AppColors.lenderBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(riderName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        const Text('Rider',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  StatusBadge(status: status),
                ],
              ),
              const Divider(height: 20),
              Row(
                children: [
                  _InfoChip(
                      Icons.attach_money,
                      amountCollected > 0
                          ? amountCollected.toCurrency
                          : 'Pending',
                      'Amount'),
                  const SizedBox(width: 12),
                  _InfoChip(
                      Icons.calendar_today_outlined,
                      scheduledAt != null
                          ? DateTime.tryParse(scheduledAt)?.toShortDate ?? '-'
                          : '-',
                      'Scheduled'),
                ],
              ),
              if (completedAt != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                        'Completed ${DateTime.tryParse(completedAt)?.toShortDate ?? ''}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.success)),
                  ],
                ),
              ],
              if (status == 'accepted' || status == 'pending') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/lender/track-rider/${item['rider_id']}'),
                    icon: const Icon(Icons.location_on_outlined, size: 16),
                    label: const Text('Track Rider'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.lenderBlue,
                      side: const BorderSide(color: AppColors.lenderBlue),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _InfoChip(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textTertiary)),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
