// lib/presentation/features/rider/dashboard/screens/rider_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 14),
                      _buildHero(context, state),
                      const SizedBox(height: 14),
                      _buildQuickActions(context),
                      const SizedBox(height: 20),
                      _buildStatCard(context, state),
                      const SizedBox(height: 20),
                      _buildSectionLabel(context,
                        label: 'Today\'s Collections',
                        count: state.todayCollections.length,
                        icon: Icons.payments_outlined,
                        onMore: () =>
                            context.push(RouteConstants.riderCollections),
                      ),
                      const SizedBox(height: 10),
                      _buildCollectionTasks(context, state),
                      const SizedBox(height: 20),
                      _buildSectionLabel(context,
                        label: 'CI Assignments',
                        count: state.todayCiTasks.length,
                        icon: Icons.search_outlined,
                        onMore: () => context.push(RouteConstants.riderCi),
                      ),
                      const SizedBox(height: 10),
                      _buildCiTasks(context, state),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildShimmer() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: List.generate(
          6,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: ShimmerLoader(height: 92, borderRadius: 20),
          ),
        ),
      );

  Widget _buildHeader(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.riderGreen, AppColors.riderGreenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.riderGreen.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -30,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 30,
            bottom: -34,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.directions_bike,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good ${_greeting()}, Rider!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Here\'s your day at a glance',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  now.formatted,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
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

  Widget _buildHero(BuildContext context, dynamic state) {
    final kpi = state.kpi;
    final ratio = kpi.totalAssignedCollections > 0
        ? (kpi.totalCompletedCollections / kpi.totalAssignedCollections)
            .clamp(0.0, 1.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.gold, Color(0xFFE9A23B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.savings_outlined,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Total Collected',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${kpi.totalCompletedCollections}/${kpi.totalAssignedCollections} done',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.riderGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CountUpText(
            endValue: kpi.totalAmountCollected,
            prefix: '₱',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.riderGreen),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.payments,
            label: 'Collections',
            colors: const [AppColors.riderGreen, AppColors.riderGreenDark],
            onTap: () => context.push(RouteConstants.riderCollections),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickAction(
            icon: Icons.fact_check_outlined,
            label: 'CI Tasks',
            colors: const [AppColors.info, Color(0xFF2E7CF6)],
            onTap: () => context.push(RouteConstants.riderCi),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, dynamic state) {
    final kpi = state.kpi;
    final ciRatio = kpi.totalCiAssignments > 0
        ? (kpi.totalCiCompleted / kpi.totalCiAssignments).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              _MiniStat(
                label: 'Assigned',
                value: kpi.totalAssignedCollections.toString(),
                icon: Icons.assignment_outlined,
                color: AppColors.info,
              ),
              _buildDivider(),
              _MiniStat(
                label: 'Completed',
                value: kpi.totalCompletedCollections.toString(),
                icon: Icons.check_circle_outline,
                color: AppColors.success,
              ),
              _buildDivider(),
              _MiniStat(
                label: 'Failed',
                value: kpi.totalFailedCollections.toString(),
                icon: Icons.cancel_outlined,
                color: AppColors.error,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
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
                      color: AppColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.search_outlined,
                        color: AppColors.info, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'CI Tasks',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${kpi.totalCiCompleted}/${kpi.totalCiAssignments}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.info,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: ciRatio,
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation(AppColors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() =>
      Container(width: 1, height: 38, color: AppColors.border);

  Widget _buildSectionLabel(
    BuildContext context, {
    required String label,
    required int count,
    required IconData icon,
    required VoidCallback onMore,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.riderGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: AppColors.riderGreen, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (count > 0)
          GestureDetector(
            onTap: onMore,
            child: const Text(
              'View all',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.riderGreen,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCollectionTasks(BuildContext context, dynamic state) {
    if (state.todayCollections.isEmpty) {
      return _buildEmptyCard(
          'No active collection tasks today', Icons.inbox_outlined);
    }
    return Column(
      children: state.todayCollections.take(5).map<Widget>((c) {
        final schedule = c.collectionSchedule?.toDateString();
        final loanNo = c.loanNumber;
        final subtitle = loanNo.isNotEmpty
            ? 'Loan $loanNo · $schedule'
            : schedule ?? 'Scheduled';
        return _buildTaskCard(
          context,
          title: 'Collection #${c.id.substring(0, 8).toUpperCase()}',
          subtitle: subtitle,
          status: c.statusLabel,
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
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
            const Icon(Icons.chevron_right,
                color: AppColors.textTertiary, size: 18),
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
        borderRadius: BorderRadius.circular(16),
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
      case 'failed':
        return AppColors.statusRejected;
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

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}