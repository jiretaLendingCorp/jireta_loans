// ignore_for_file: prefer_const_constructors
// lib/presentation/features/rider/ci/screens/rider_ci_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/utils/timezone.dart';
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
    MobileNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: RouteConstants.riderDashboard),
    MobileNavItem(
        icon: Icons.payments_outlined,
        activeIcon: Icons.payments,
        label: 'Collections',
        route: RouteConstants.riderCollections),
    MobileNavItem(
        icon: Icons.search_outlined,
        activeIcon: Icons.search,
        label: 'CI Tasks',
        route: RouteConstants.riderCi),
    MobileNavItem(
        icon: Icons.history_outlined,
        activeIcon: Icons.history_rounded,
        label: 'History',
        route: RouteConstants.riderHistory),
    MobileNavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
        route: RouteConstants.riderProfile),
  ];

  // May "Declined" tab sa tabi ng Completed para makita pa rin ng rider ang
  // mga assignment na tinanggihan nila (dati'y tuluyang nawawala sa listahan).
  final _tabs = ['Assigned', 'In Progress', 'Completed', 'Declined'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final statusMap = ['assigned', 'in_progress', 'completed', 'declined'];
    ref
        .read(riderCiProvider.notifier)
        .setFilter(statusMap[_tabController.index]);
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
          // Pareho sa Collections: nakadikit sa header (walang gap) — green
          // (o itim sa dark mode) ang tab strip, puting label, gold indicator.
          Container(
            color: context.headerColor(AppColors.riderGreen),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.gold,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : RefreshIndicator(
                    color: AppColors.riderGreen,
                    onRefresh: () =>
                        ref.read(riderCiProvider.notifier).refresh(),
                    child: state.investigations.isEmpty
                        ? const EmptyStateWidget(
                            message: 'No CI assignments found')
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            // Siksik na listahan — mas maliit na side/top padding
                            // at masikip na pagitan ng mga card.
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
                            itemCount: state.investigations.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (ctx, i) => _CiCard(
                              key: ValueKey(state.investigations[i].id),
                              ci: state.investigations[i],
                              onTap: () => ctx.push(
                                  '${RouteConstants.riderCi}/${state.investigations[i].id}'),
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
  const _CiCard({super.key, required this.ci, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final deadline = ci.deadline != null
        ? DateFormat('MMM d, yyyy').format(ci.deadline!)
        : 'N/A';
    final isUrgent = ci.deadline != null &&
        ci.deadline!.difference(nowManila()).inDays <= 2;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: context.cSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isUrgent
                  ? AppColors.error.withValues(alpha: 0.3)
                  : context.cBorder),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: AppColors.lenderBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.search,
                      color: AppColors.lenderBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          ci.borrowerName.isEmpty
                              ? 'Lender'
                              : ci.borrowerName,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.cTextPrimary)),
                      Text('Loan #${ci.loanNumber}',
                          style: TextStyle(
                              fontSize: 12, color: context.cTextSecondary)),
                    ],
                  ),
                ),
                StatusBadge(status: ci.status == 'accepted' ? 'in_progress' : ci.status),
              ],
            ),
            const SizedBox(height: 9),
            const Divider(height: 1),
            const SizedBox(height: 9),
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
                    value: DateFormat('MMM d, yyyy h:mm a').format(ci.assignedAt),
                  ),
                ),
              ],
            ),
            if (ci.investigationNotes != null &&
                ci.investigationNotes!.isNotEmpty) ...[
              const SizedBox(height: 7),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(ci.investigationNotes!,
                    style: TextStyle(
                        fontSize: 12, color: context.cTextSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
            if (ci.status == 'assigned') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleDecline(context),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(vertical: 9)),
                      child:
                          Text('Decline', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _handleAccept(context),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.riderGreen,
                          padding: const EdgeInsets.symmetric(vertical: 9)),
                      child: Text('Accept',
                          style: TextStyle(fontSize: 13, color: Colors.white)),
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
          title: Text('Accept CI Assignment'),
          content: Text(
              'Are you sure you want to accept this credit investigation assignment?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.riderGreen),
              onPressed: () async {
                Navigator.pop(ctx);
                await ref.read(riderCiProvider.notifier).accept(ci.id);
              },
              child:
                  Text('Accept', style: TextStyle(color: Colors.white)),
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
          title: Text('Decline CI Assignment'),
          content:
              Text('Are you sure you want to decline this assignment?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () async {
                Navigator.pop(ctx);
                await ref.read(riderCiProvider.notifier).decline(ci.id);
              },
              child:
                  Text('Decline', style: TextStyle(color: Colors.white)),
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
  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: context.cTextTertiary),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: context.cTextTertiary)),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? context.cTextPrimary)),
          ],
        ),
      ],
    );
  }
}
