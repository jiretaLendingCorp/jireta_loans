// lib/presentation/features/rider/collections/screens/rider_collection_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/rider_collection_provider.dart';

class RiderCollectionListScreen extends ConsumerStatefulWidget {
  const RiderCollectionListScreen({super.key});

  @override
  ConsumerState<RiderCollectionListScreen> createState() =>
      _RiderCollectionListScreenState();
}

class _RiderCollectionListScreenState
    extends ConsumerState<RiderCollectionListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _tabs = ['pending', 'accepted', 'completed', 'declined'];
  final _tabLabels = ['Pending', 'Accepted', 'Completed', 'Declined'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        ref
            .read(riderCollectionProvider.notifier)
            .setTab(_tabs[_tabCtrl.index]);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCollectionProvider);

    return MobileScaffold(
      title: 'Collections',
      accentColor: AppColors.riderGreen,
      navItems: const [
        MobileNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          label: 'Home',
          route: RouteConstants.riderDashboard,
        ),
        MobileNavItem(
          icon: Icons.payments_outlined,
          activeIcon: Icons.payments,
          label: 'Collections',
          route: RouteConstants.riderCollections,
        ),
        MobileNavItem(
          icon: Icons.search_outlined,
          activeIcon: Icons.search,
          label: 'CI Tasks',
          route: RouteConstants.riderCi,
        ),
        MobileNavItem(
          icon: Icons.notifications_outlined,
          activeIcon: Icons.notifications,
          label: 'Notifications',
          route: RouteConstants.riderNotifications,
        ),
        MobileNavItem(
          icon: Icons.person_outline,
          activeIcon: Icons.person,
          label: 'Profile',
          route: RouteConstants.riderProfile,
        ),
      ],
      body: Column(
        children: [
          Container(
            color: AppColors.riderGreen,
            child: TabBar(
              controller: _tabCtrl,
              indicatorColor: AppColors.gold,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
            ),
          ),
          Expanded(
            child: state.isLoading
                ? ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 5,
                    itemBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: ShimmerLoader(height: 90, borderRadius: 12),
                    ),
                  )
                : state.collections.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        color: AppColors.riderGreen,
                        onRefresh: () => ref
                            .read(riderCollectionProvider.notifier)
                            .refresh(),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: state.collections.length,
                          itemBuilder: (_, i) =>
                              _buildCard(context, state.collections[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined,
              size: 64, color: AppColors.textTertiary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'No collections found',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, dynamic c) {
    final loanSchedule = c.loanSchedule as Map<String, dynamic>?;
    final lenderName = loanSchedule?['loan']?['lender'] != null
        ? '${loanSchedule!['loan']['lender']['first_name']} ${loanSchedule['loan']['lender']['last_name']}'
        : 'Lender';
    final amountDue = loanSchedule?['installment_amount']?.toString() ?? '0.00';
    final dueDate = loanSchedule?['due_date'] != null
        ? DateTime.tryParse(loanSchedule!['due_date'])?.toDateString() ?? ''
        : '';

    return GestureDetector(
      onTap: () => context.push('${RouteConstants.riderCollections}/${c.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.riderGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.payments_outlined,
                      color: AppColors.riderGreen, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lenderName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Due: $dueDate',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(status: c.status),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _infoChip(Icons.money, '₱$amountDue due'),
                if (c.collectionSchedule != null)
                  _infoChip(
                      Icons.schedule, c.collectionSchedule!.toDateTimeString()),
                _infoChip(Icons.chevron_right, 'View Details'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
