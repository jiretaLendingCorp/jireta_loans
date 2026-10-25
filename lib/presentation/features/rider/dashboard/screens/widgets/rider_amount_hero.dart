// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
// lib/presentation/features/rider/dashboard/screens/widgets/rider_amount_hero.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/route_constants.dart';
import '../../../../../../core/extensions/num_extensions.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../data/models/rider_quota_model.dart';
import '../../../../../shared/widgets/animated/count_up_animation.dart';
import '../../../quota/providers/rider_quota_provider.dart';
import '../../providers/rider_dashboard_provider.dart';

/// Total Collected hero card ng rider dashboard.
///
/// Nasa LOOB nito ang quota (hal. weekly) — sa TAAS ng nakolektang halaga —
/// kaya hindi na kailangan ng hiwalay pang quota card sa ibaba.

class RiderAmountHero extends StatelessWidget {
  final RiderDashboardState state;
  const RiderAmountHero({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final kpi = state.kpi;
    // Ratio / progress indicators (ang "4/5 done" chip at ang horizontal
    // progress line) ay sadyang hindi na ipinapakita — ang halaga lang ang
    // pokus ng Total Collected card.
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.riderGreen, AppColors.riderGreenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.riderGreen.withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -28,
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
            right: 36,
            bottom: -32,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -16,
            bottom: -20,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Weekly quota — sa LOOB ng Total Collected card, sa TAAS ng
              // halaga. Walang sariling card background at walang separating
              // line — bahagi lang ito ng hero card.
              const _HeroQuotaStrip(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.32),
                          width: 1.3),
                    ),
                    child: Icon(Icons.savings_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL COLLECTED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.9,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.selectedDate != null
                              ? 'Collections on ${state.selectedDate}'
                              : (state.selectedMonth != null
                                  ? 'Monthly collections — ${RiderDashboardNotifier.monthLabel(state.selectedMonth!)}'
                                  : 'All-time field collections'),
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: CountUpAnimation(
                  value: kpi.totalAmountCollected,
                  prefix: '₱',
                  decimalPlaces: 2,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.8,
                    shadows: [
                      Shadow(
                          color: Color(0x20000000),
                          blurRadius: 8,
                          offset: Offset(0, 2))
                    ],
                  ),
                ),
              ),
              // Walang "N failed" chip dito — ang mga failed collection ay
              // nasa History (kasama sa feed), hindi sa Total Collected card.
            ],
          ),
        ],
      ),
    );
  }
}

/// Quota (hal. weekly) sa LOOB ng Total Collected card — nasa TAAS ng halaga.
/// Walang sariling card background o border: nakapatong lang ito sa berdeng
/// hero, kaya hindi doble ang "card sa loob ng card".
///
/// Kulay: puti ang progress bar habang hindi pa naabot ang target, gold kapag
/// achieved. Hindi na ginagamit ang red/amber/green na coding ng dating
/// standalone card dahil hindi ito mababasa sa berdeng gradient.
class _HeroQuotaStrip extends ConsumerWidget {
  const _HeroQuotaStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(riderQuotaProvider);
    final current = state.data?.current;
    final percent = current?.completionPercentage;
    final achieved = current?.achieved ?? false;
    final accent = achieved ? AppColors.gold : Colors.white;

    return InkWell(
      onTap: () => context.push(RouteConstants.riderMyQuota),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined,
                  size: 14, color: Colors.white.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  current == null
                      ? 'MY QUOTA'
                      : '${RiderQuotaPeriod.label(current.period)} QUOTA'
                          .toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
              if (current != null)
                Text(
                  percent == null ? '—' : '${percent.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: Colors.white.withValues(alpha: 0.7)),
            ],
          ),
          const SizedBox(height: 6),
          if (current == null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                state.isLoading
                    ? 'Loading your quota…'
                    : 'No quota assigned yet — tap to see details.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                '${current.confirmedCollection.toPeso()} of '
                '${current.targetAmount.toPeso()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  // Nakasentro sa 100% ang haba ng bar, pero ang TEXT sa
                  // itaas ay ang totoong porsyento (hal. 125.0%).
                  value: ((percent ?? 0) / 100).clamp(0.0, 1.0).toDouble(),
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
