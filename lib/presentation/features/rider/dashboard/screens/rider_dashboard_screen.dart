// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
// lib/presentation/features/rider/dashboard/screens/rider_dashboard_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/asset_constants.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/animated/count_up_animation.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../dashboard/providers/rider_dashboard_provider.dart';
import '../../profile/providers/rider_profile_provider.dart';

class RiderDashboardScreen extends ConsumerStatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  ConsumerState<RiderDashboardScreen> createState() =>
      _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends ConsumerState<RiderDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderDashboardProvider);
    final profileState = ref.watch(riderProfileProvider);
    final riderName = _resolveRiderName(profileState);

    return MobileScaffold(
      title: 'Rider Home',
      accentColor: AppColors.riderGreen,
      navItems: const [
        MobileNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          label: 'Home',
          route: RouteConstants.riderDashboard,
        ),
        MobileNavItem(
          icon: Icons.delivery_dining_outlined,
          activeIcon: Icons.delivery_dining,
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
              onRefresh: () async {
                await ref.read(riderDashboardProvider.notifier).refresh();
                await ref.read(riderProfileProvider.notifier).refresh();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Entrance(
                      delay: 0,
                      child: _EnterpriseHeader(
                        riderName: riderName,
                        profilePhotoUrl: profileState.user?.profilePhotoUrl,
                        taskCount: state.todayCollections.length +
                            state.todayDeliveries.length +
                            state.todayCiTasks.length,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Entrance(
                      delay: 80,
                      child: _EnterpriseAmountHero(state: state),
                    ),
                    const SizedBox(height: 22),
                    _Entrance(
                      delay: 180,
                      child: _buildSectionLabel(
                        context,
                        label: 'Collections',
                        count: state.todayCollections.length,
                        icon: Icons.delivery_dining_outlined,
                        onMore: () =>
                            context.push(RouteConstants.riderCollections),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Entrance(
                        delay: 220,
                        child: _buildCollectionTasks(context, state)),
                    const SizedBox(height: 20),
                    _Entrance(
                      delay: 280,
                      child: _buildSectionLabel(
                        context,
                        label: 'Cash Deliveries',
                        count: state.todayDeliveries.length,
                        icon: Icons.delivery_dining_outlined,
                        onMore: () =>
                            context.push(RouteConstants.riderDisbursements),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Entrance(
                        delay: 340, child: _buildDeliveryTasks(context, state)),
                    const SizedBox(height: 20),
                    _Entrance(
                      delay: 400,
                      child: _buildSectionLabel(
                        context,
                        label: 'CI Assignments',
                        count: state.todayCiTasks.length,
                        icon: Icons.search_outlined,
                        onMore: () => context.push(RouteConstants.riderCi),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Entrance(delay: 460, child: _buildCiTasks(context, state)),
                    if (state.error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(state.error!),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
    );
  }

  String _resolveRiderName(RiderProfileState p) {
    final u = p.user;
    if (u == null) return 'Rider';
    final first = u.firstName.trim();
    final last = u.lastName.trim();
    final full = ('$first $last').trim();
    if (full.isEmpty) return 'Rider';
    return full;
  }

  Widget _buildShimmer() => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
        child: Column(
          children: [
            const ShimmerLoader(height: 112, borderRadius: 16),
            const SizedBox(height: 14),
            const ShimmerLoader(height: 154, borderRadius: 20),
            const SizedBox(height: 20),
            ...List.generate(
              5,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: ShimmerLoader(height: 72, borderRadius: 16),
              ),
            ),
          ],
        ),
      );

  Widget _buildSectionLabel(
    BuildContext context, {
    required String label,
    required int count,
    required IconData icon,
    required VoidCallback onMore,
  }) {
    final hasItems = count > 0;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.riderGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: AppColors.riderGreen, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (hasItems) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.riderGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.riderGreen,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (hasItems)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onMore,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'View all',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.riderGreen,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 16, color: AppColors.riderGreen),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCollectionTasks(BuildContext context, RiderDashboardState state) {
    if (state.todayCollections.isEmpty) {
      return _buildEmptyCard('No assigned collection tasks yet', Icons.inbox_outlined);
    }
    return Column(
      children: state.todayCollections.take(5).map<Widget>((c) {
        final lender = c.lenderName;
        final subtitle = lender.isNotEmpty ? 'To: $lender' : 'Loan ${c.loanNumber}';
        return _buildTaskCard(
          context,
          title: 'Collection #${c.id.substring(0, 8).toUpperCase()}',
          subtitle: subtitle,
          status: c.statusLabel,
          statusColor: _collStatusColor(c.status),
          icon: Icons.delivery_dining_outlined,
          iconColor: AppColors.riderGreen,
          onTap: () => context.push('${RouteConstants.riderCollections}/${c.id}'),
        );
      }).toList(),
    );
  }

  Widget _buildDeliveryTasks(BuildContext context, RiderDashboardState state) {
    if (state.todayDeliveries.isEmpty) {
      return _buildEmptyCard('No cash deliveries assigned', Icons.delivery_dining_outlined);
    }
    return Column(
      children: state.todayDeliveries.take(5).map<Widget>((d) {
        final delivery = d.deliveryDate;
        final lender = d.lenderName;
        final subtitle = lender.isNotEmpty ? 'To: $lender' : 'Loan ${d.loanNumber}';
        return _buildTaskCard(
          context,
          title: 'Loan ${d.loanNumber}',
          subtitle: delivery != null ? '$subtitle · Due ${delivery.toDateString()}' : subtitle,
          status: 'Deliver',
          statusColor: AppColors.gold,
          icon: Icons.delivery_dining_outlined,
          iconColor: AppColors.gold,
          onTap: () => context.push(RouteConstants.riderDisbursementUploadProof.replaceFirst(':id', d.id)),
        );
      }).toList(),
    );
  }

  Widget _buildCiTasks(BuildContext context, RiderDashboardState state) {
    if (state.todayCiTasks.isEmpty) {
      return _buildEmptyCard('No active CI tasks today', Icons.search_off);
    }
    return Column(
      children: state.todayCiTasks.take(5).map<Widget>((ci) {
        return _buildTaskCard(
          context,
          title: 'CI Task #${ci.id.substring(0, 8).toUpperCase()}',
          subtitle: ci.deadline != null ? 'Due: ${ci.deadline!.toDateString()}' : 'No deadline',
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 0,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 92),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text(status.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor, letterSpacing: 0.3)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCard(String message, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 36),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Color _collStatusColor(String s) {
    switch (s) {
      case 'pending':
        return AppColors.statusPending;
      case 'assigned':
        return AppColors.info;
      case 'accepted':
      case 'in_progress':
        return AppColors.riderGreen;
      case 'completed':
        return AppColors.statusCompleted;
      case 'failed':
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
      case 'in_progress':
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

class _EnterpriseHeader extends StatelessWidget {
  final String riderName;
  final String? profilePhotoUrl;
  final int taskCount;
  const _EnterpriseHeader({required this.riderName, this.profilePhotoUrl, required this.taskCount});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final h = now.hour;
    final String greeting;
    final IconData greetingIcon;
    final Color greetingColor;
    if (h >= 5 && h < 12) {
      greeting = 'Good Morning';
      greetingIcon = Icons.wb_sunny_rounded;
      greetingColor = const Color(0xFFE9A23B);
    } else if (h >= 12 && h < 18) {
      greeting = 'Good Afternoon';
      greetingIcon = Icons.light_mode_rounded;
      greetingColor = AppColors.goldDark;
    } else {
      greeting = 'Good Evening';
      greetingIcon = Icons.nights_stay_rounded;
      greetingColor = const Color(0xFF4A5A78);
    }
    final subText = taskCount == 0 ? 'No tasks queued — enjoy the calm' : taskCount == 1 ? 'You have 1 active task today' : 'You have $taskCount active tasks today';
    final initials = riderName.trim().isEmpty ? 'R' : riderName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    // NO CARD — text only, profile left, hi right, logo left upper, visible borders
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Jireta logo — RIGHT side, black visible border, BILOG fit
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1.6),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 7, offset: const Offset(0, 2))],
              ),
              child: ClipOval(
                child: Image.asset(AssetConstants.logoJpg, fit: BoxFit.cover, width: 30, height: 30, errorBuilder: (_, __, ___) => const Icon(Icons.shield_rounded, size: 15, color: Colors.black)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 38, top: 0, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile picture — LEFT side, visible black edge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2.2),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 10, offset: const Offset(0, 3)), BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      alignment: Alignment.center,
                      child: ClipOval(
                        child: profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty
                            ? Image.network(profilePhotoUrl!, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initialsText(initials))
                            : _initialsText(initials),
                      ),
                    ),
                    Positioned(right: -1, bottom: -1, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: AppColors.riderGreen, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
                  ],
                ),
                const SizedBox(width: 12),
                // Hi + name — RIGHT side of profile picture, text only
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: greetingColor.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(20), border: Border.all(color: greetingColor.withValues(alpha: 0.16))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(greetingIcon, size: 11, color: greetingColor), const SizedBox(width: 3), Text(greeting.toUpperCase(), style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: greetingColor))])),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)), child: Text(now.formatted, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Hi, $riderName!', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3, height: 1.1)),
                      const SizedBox(height: 2),
                      Text(subText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _initialsText(String initials) => Text(initials, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.riderGreen, letterSpacing: 0.5));
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool dot;
  const _MetaChip({required this.icon, required this.label, required this.color, this.dot = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(7), border: Border.all(color: color.withValues(alpha: 0.14))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [if (dot) Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)) else Icon(icon, size: 11, color: color), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color))]),
    );
  }
}

class _EnterpriseAmountHero extends StatelessWidget {
  final RiderDashboardState state;
  const _EnterpriseAmountHero({required this.state});
  @override
  Widget build(BuildContext context) {
    final kpi = state.kpi;
    final ratio = kpi.totalAssignedCollections > 0 ? (kpi.totalCompletedCollections / kpi.totalAssignedCollections).clamp(0.0, 1.0) : 0.0;
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.riderGreen, AppColors.riderGreenDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.riderGreen.withValues(alpha: 0.32), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          Positioned(right: -18, top: -28, child: Container(width: 110, height: 110, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle))),
          Positioned(right: 36, bottom: -32, child: Container(width: 74, height: 74, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle))),
          Positioned(left: -16, bottom: -20, child: Container(width: 88, height: 88, decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.10), shape: BoxShape.circle))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.32), width: 1.3)), child: const Icon(Icons.savings_rounded, color: Colors.white, size: 20)),
                  const SizedBox(width: 11),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TOTAL COLLECTED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: Colors.white70)), SizedBox(height: 2), Text('All-time field collections', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600))])),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2))]), child: Text('${kpi.totalCompletedCollections}/${kpi.totalAssignedCollections} done', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.riderGreen))),
                ],
              ),
              const SizedBox(height: 16),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: CountUpAnimation(value: kpi.totalAmountCollected, prefix: '₱', decimalPlaces: 2, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.8, shadows: [Shadow(color: Color(0x20000000), blurRadius: 8, offset: Offset(0, 2))]))),
              const SizedBox(height: 14),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ratio, minHeight: 7, backgroundColor: Colors.white.withValues(alpha: 0.22), valueColor: const AlwaysStoppedAnimation(AppColors.gold))),
              const SizedBox(height: 8),
              Row(children: [const Icon(Icons.trending_up_rounded, size: 13, color: Colors.white70), const SizedBox(width: 6), Expanded(child: Text(ratio == 1 && kpi.totalAssignedCollections > 0 ? 'All collections completed — excellent field work!' : '${(ratio * 100).toStringAsFixed(0)}% of assigned collections completed', style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600))), if (kpi.totalFailedCollections > 0) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)), child: Text('${kpi.totalFailedCollections} failed', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)))]]),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  const _ErrorBanner(this.error);
  @override
  Widget build(BuildContext context) {
    return Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.error.withValues(alpha: 0.25))), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.error_outline, color: AppColors.error, size: 18), const SizedBox(width: 8), Expanded(child: Text(error, style: const TextStyle(color: AppColors.error, fontSize: 12)))]));
  }
}

class _Entrance extends StatefulWidget {
  final Widget child;
  final int delay;
  const _Entrance({required this.child, this.delay = 0});
  @override
  State<_Entrance> createState() => _EntranceState();
}
class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  late final Animation<double> _scale;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _offset = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved);
    _scale = Tween<double>(begin: 0.97, end: 1).animate(curved);
    _timer = Timer(Duration(milliseconds: widget.delay), () { if (mounted) _ctrl.forward(); });
  }
  @override
  void dispose() { _timer?.cancel(); _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) { return FadeTransition(opacity: _opacity, child: SlideTransition(position: _offset, child: ScaleTransition(scale: _scale, child: widget.child))); }
}
