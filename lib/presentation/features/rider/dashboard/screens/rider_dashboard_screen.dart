// lib/presentation/features/rider/dashboard/screens/rider_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/animated/count_up_animation.dart';
import '../../dashboard/providers/rider_dashboard_provider.dart';

class RiderDashboardScreen extends ConsumerStatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  ConsumerState<RiderDashboardScreen> createState() =>
      _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends ConsumerState<RiderDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderDashboardProvider);

    return MobileScaffold(
      title: 'Rider Dashboard',
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
      body: state.isLoading
          ? _buildShimmer()
          : RefreshIndicator(
              color: AppColors.riderGreen,
              onRefresh: () =>
                  ref.read(riderDashboardProvider.notifier).refresh(),
              child: FadeTransition(
                opacity: _fadeCtrl,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 16),
                      _buildKpiGrid(state),
                      const SizedBox(height: 20),
                      _buildSectionLabel('Today\'s Collections'),
                      const SizedBox(height: 10),
                      _buildCollectionTasks(context, state),
                      const SizedBox(height: 20),
                      _buildSectionLabel('CI Assignments'),
                      const SizedBox(height: 10),
                      _buildCiTasks(context, state),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildShimmer() => ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(
          6,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: ShimmerLoader(height: 80, borderRadius: 12),
          ),
        ),
      );

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.riderGreen, AppColors.riderGreenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.directions_bike,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good ${_greeting()}!',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const Text(
                  'Rider',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Text(
            DateTime.now().toDateString(),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Morning';
    if (h < 17) return 'Afternoon';
    return 'Evening';
  }

  Widget _buildSectionLabel(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      );

  Widget _buildKpiGrid(dynamic state) {
    final kpi = state.kpi;
    final items = [
      _KpiItem('Total Assigned', kpi.totalAssignedCollections.toString(),
          Icons.assignment, AppColors.riderGreen),
      _KpiItem('Completed', kpi.totalCompletedCollections.toString(),
          Icons.check_circle_outline, AppColors.success),
      _KpiItem('Failed', kpi.totalFailedCollections.toString(),
          Icons.cancel_outlined, AppColors.error),
      _KpiItem('Collected', '₱${NumberFormat('#,##0.00', 'en_PH').format(kpi.totalAmountCollected)}',
          Icons.payments, AppColors.gold),
      _KpiItem('CI Assigned', kpi.totalCiAssignments.toString(), Icons.search,
          AppColors.info),
      _KpiItem('CI Done', kpi.totalCiCompleted.toString(),
          Icons.verified_outlined, AppColors.riderGreenDark),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildKpiCard(items[i]),
    );
  }

  Widget _buildKpiCard(_KpiItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(item.icon, color: item.color, size: 18),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          CountUpText(
            endValue: _parseNum(item.value),
            prefix: item.value.startsWith('₱') ? '₱' : '',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  double _parseNum(String v) {
    final cleaned = v.replaceAll(RegExp(r'[₱,]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  Widget _buildCollectionTasks(BuildContext context, dynamic state) {
    if (state.todayCollections.isEmpty) {
      return _buildEmptyCard(
          'No active collection tasks today', Icons.inbox_outlined);
    }
    return Column(
      children: state.todayCollections.take(5).map<Widget>((c) {
        return _buildTaskCard(
          context,
          title: 'Collection #${c.id.substring(0, 8).toUpperCase()}',
          subtitle: c.collectionSchedule?.toDateString() ?? 'Scheduled',
          status: c.status,
          statusColor: _collStatusColor(c.status),
          icon: Icons.payments_outlined,
          iconColor: AppColors.riderGreen,
          onTap: () =>
              context.push('${RouteConstants.riderCollections}/${c.id}'),
        );
      }).toList(),
    );
  }

  Widget _buildCiTasks(BuildContext context, dynamic state) {
    if (state.todayCiTasks.isEmpty) {
      return _buildEmptyCard('No active CI tasks today', Icons.search_off);
    }
    return Column(
      children: state.todayCiTasks.take(5).map<Widget>((ci) {
        return _buildTaskCard(
          context,
          title: 'CI Task #${ci.id.substring(0, 8).toUpperCase()}',
          subtitle: ci.deadline != null
              ? 'Due: ${ci.deadline!.toDateString()}'
              : 'No deadline',
          status: ci.status,
          statusColor: _ciStatusColor(ci.status),
          icon: Icons.search_outlined,
          iconColor: AppColors.info,
          onTap: () => context.push('${RouteConstants.riderCi}/${ci.id}'),
        );
      }).toList(),
    );
  }

  Widget _buildTaskCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String status,
    required Color statusColor,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 36),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Color _collStatusColor(String s) {
    switch (s) {
      case 'pending':
        return AppColors.statusPending;
      case 'accepted':
        return AppColors.riderGreen;
      case 'completed':
        return AppColors.statusCompleted;
      case 'declined':
        return AppColors.statusRejected;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _ciStatusColor(String s) {
    switch (s) {
      case 'pending':
        return AppColors.statusPending;
      case 'accepted':
        return AppColors.info;
      case 'completed':
        return AppColors.statusCompleted;
      case 'declined':
        return AppColors.statusRejected;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _KpiItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiItem(this.label, this.value, this.icon, this.color);
}
