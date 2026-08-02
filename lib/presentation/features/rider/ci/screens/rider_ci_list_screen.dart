// lib/presentation/features/rider/ci/screens/rider_ci_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/rider_ci_provider.dart';

class RiderCiListScreen extends ConsumerStatefulWidget {
  const RiderCiListScreen({super.key});

  @override
  ConsumerState<RiderCiListScreen> createState() => _RiderCiListScreenState();
}

class _RiderCiListScreenState extends ConsumerState<RiderCiListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _navItems = [
    MobileNavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', route: RouteConstants.riderDashboard),
    MobileNavItem(icon: Icons.payments_outlined, activeIcon: Icons.payments, label: 'Collections', route: RouteConstants.riderCollections),
    MobileNavItem(icon: Icons.search_outlined, activeIcon: Icons.search, label: 'CI Tasks', route: RouteConstants.riderCi),
    MobileNavItem(icon: Icons.notifications_outlined, activeIcon: Icons.notifications, label: 'Notifications', route: RouteConstants.riderNotifications),
    MobileNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile', route: RouteConstants.riderProfile),
  ];

  final _tabs = ['Pending', 'Accepted', 'In Progress', 'Completed'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final statusMap = ['pending', 'accepted', 'in_progress', 'completed'];
    ref.read(riderCiProvider.notifier).setFilter(statusMap[_tabController.index]);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderCiProvider);

    return MobileScaffold(
      title: 'CI Tasks',
      accentColor: AppColors.riderGreen,
      navItems: _navItems,
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.riderGreen,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.riderGreen,
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : RefreshIndicator(
                    color: AppColors.riderGreen,
                    onRefresh: () => ref.read(riderCiProvider.notifier).refresh(),
                    child: state.investigations.isEmpty
                        ? const EmptyStateWidget(message: 'No CI assignments found')
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: state.investigations.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (ctx, i) => _CiCard(
                              ci: state.investigations[i],
                              onTap: () => ctx.push('${RouteConstants.riderCi}/${state.investigations[i].id}'),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CiCard extends StatelessWidget {
  final CreditInvestigationModel ci;
  final VoidCallback onTap;
  const _CiCard({required this.ci, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final deadline = ci.deadline != null ? DateFormat('MMM d, yyyy').format(ci.deadline!) : 'N/A';
    final isUrgent = ci.deadline != null && ci.deadline!.difference(DateTime.now()).inDays <= 2;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isUrgent ? AppColors.error.withValues(alpha: 0.3) : AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.lenderPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.search, color: AppColors.lenderPurple, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ci.borrowerName.isEmpty ? 'Borrower' : ci.borrowerName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      Text('Loan #${ci.loanNumber}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                StatusBadge(status: ci.status),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Deadline',
                    value: deadline,
                    valueColor: isUrgent ? AppColors.error : null,
                  ),
                ),
                Expanded(
                  child: _InfoRow(
                    icon: Icons.access_time,
                    label: 'Assigned',
                    value: DateFormat('MMM d').format(ci.assignedAt),
                  ),
                ),
              ],
            ),
            if (ci.investigationNotes != null && ci.investigationNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
                child: Text(ci.investigationNotes!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
            if (ci.status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleDecline(context),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error), padding: const EdgeInsets.symmetric(vertical: 10)),
                      child: const Text('Decline', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _handleAccept(context),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.riderGreen, padding: const EdgeInsets.symmetric(vertical: 10)),
                      child: const Text('Accept', style: TextStyle(fontSize: 13, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleAccept(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final ref = ProviderScope.containerOf(ctx);
        return AlertDialog(
          title: const Text('Accept CI Assignment'),
          content: const Text('Are you sure you want to accept this credit investigation assignment?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.riderGreen),
              onPressed: () async {
                Navigator.pop(ctx);
                await ref.read(riderCiProvider.notifier).accept(ci.id);
              },
              child: const Text('Accept', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _handleDecline(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final ref = ProviderScope.containerOf(ctx);
        return AlertDialog(
          title: const Text('Decline CI Assignment'),
          content: const Text('Are you sure you want to decline this assignment?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () async {
                Navigator.pop(ctx);
                await ref.read(riderCiProvider.notifier).decline(ci.id);
              },
              child: const Text('Decline', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }
}