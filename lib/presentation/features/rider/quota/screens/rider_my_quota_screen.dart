// lib/presentation/features/rider/quota/screens/rider_my_quota_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/rider_quota_model.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/rider_quota_progress.dart';
import '../providers/rider_quota_provider.dart';

/// Rider's own quota — read-only. Ang rider id ay galing sa token sa server,
/// kaya walang paraan para makita o mabago ang quota ng ibang rider dito.
class RiderMyQuotaScreen extends ConsumerWidget {
  const RiderMyQuotaScreen({super.key});

  static const _navItems = [
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
      icon: Icons.history_outlined,
      activeIcon: Icons.history_rounded,
      label: 'History',
      route: RouteConstants.riderHistory,
    ),
    MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.riderProfile,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(riderQuotaProvider);

    return MobileScaffold(
      title: 'My Quota',
      accentColor: AppColors.riderGreen,
      navItems: _navItems,
      body: RefreshIndicator(
        color: AppColors.riderGreen,
        onRefresh: () =>
            ref.read(riderQuotaProvider.notifier).load(silent: true),
        child: state.isLoading && state.data == null
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && state.data == null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      ErrorStateWidget(
                        message: state.error!,
                        onRetry: () =>
                            ref.read(riderQuotaProvider.notifier).load(),
                      ),
                    ],
                  )
                : _body(context, state.data),
      ),
    );
  }

  Widget _body(BuildContext context, RiderQuotaSelf? data) {
    final current = data?.current;
    final payments = data?.payments ?? const <RiderQuotaPayment>[];
    final history = data?.history ?? const <RiderQuota>[];
    final isWide = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    // Dalawang seksyon: magkasunod (mobile) o MAGKATABI (desktop). Sa desktop
    // kasi, kung naka-stack pa rin, daang-daang pixels ng blangkong espasyo sa
    // ibaba ng maikling listahan ang lumalabas.
    // Bawat seksyon ay isang card — hindi na mga "lumulutang" na row sa
    // page background. Sa desktop ito ang nagbibigay ng malinaw na hati ng
    // dalawang column imbes na blangkong espasyo sa ibaba ng maikling listahan.
    final historySection = _SectionCard(
      icon: Icons.receipt_long_outlined,
      title: 'Collection history',
      subtitle: current == null
          ? 'No active quota right now'
          : 'Verified payments inside the quota period',
      children: payments.isEmpty
          ? const [
              _SectionEmpty(
                icon: Icons.receipt_long_outlined,
                message:
                    'No verified collections inside this quota period yet.',
              ),
            ]
          : [
              for (var i = 0; i < payments.length; i++)
                _PaymentTile(
                  payment: payments[i],
                  divider: i < payments.length - 1,
                ),
            ],
    );

    final previousSection = _SectionCard(
      icon: Icons.history_rounded,
      title: 'Previous quotas',
      subtitle: 'Completed periods and their results',
      children: history.isEmpty
          ? const [
              _SectionEmpty(
                icon: Icons.history_rounded,
                message: 'No previous quota results yet.',
              ),
            ]
          : [
              for (var i = 0; i < history.length; i++)
                _HistoryTile(
                  quota: history[i],
                  divider: i < history.length - 1,
                ),
            ],
    );

    return Center(
      // Desktop: hindi nakaunat sa buong browser — may cap ang lapad at
      // nakasentro, kapareho ng ibang desktop na pahina. Mobile: buong lapad.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Desktop: 24px gutter — kapareho ng ibang desktop na pahina.
          // Mobile: buong lapad at may clearance para sa floating bottom nav.
          padding: isWide
              ? const EdgeInsets.fromLTRB(24, 24, 24, 40)
              : const EdgeInsets.fromLTRB(16, 18, 16, 100),
          children: [
            if (current == null)
              const _NoQuotaCard()
            else
              _CurrentQuotaCard(quota: current),
            SizedBox(height: isWide ? 20 : 18),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: historySection),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: previousSection),
                ],
              )
            else ...[
              historySection,
              const SizedBox(height: 16),
              previousSection,
            ],
          ],
        ),
      ),
    );
  }
}

class _CurrentQuotaCard extends StatelessWidget {
  final RiderQuota quota;
  const _CurrentQuotaCard({required this.quota});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, y');
    // Sa desktop, MAGKATABI ang malaking halaga at ang tatlong metric para
    // puno at balanseng tingnan ang card. Dati, naka-stack ang lahat kaya
    // umaabot sa buong lapad ang tatlong numero na may malaking blangko sa
    // pagitan. Sa mobile, naka-stack pa rin (walang lugar para sa dalawang
    // column).
    final isWide = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    final amountBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            quota.targetAmount.toPeso(),
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          quota.achieved
              ? 'Target reached'
              : '${quota.remainingTarget.toPeso()} remaining to reach the target',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12,
          ),
        ),
      ],
    );

    final metricsRow = Row(
      children: [
        Expanded(
          child: _Metric(
            label: 'Confirmed',
            value: quota.confirmedCollection.toPeso(),
          ),
        ),
        Expanded(
          child: _Metric(
            label: 'Remaining',
            value: quota.remainingTarget.toPeso(),
          ),
        ),
        Expanded(
          child: _Metric(
            label: 'Progress',
            value: quota.completionPercentage == null
                ? '—'
                : '${quota.completionPercentage!.toStringAsFixed(1)}%',
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: quota.achieved
              ? [AppColors.success, AppColors.success.withValues(alpha: 0.75)]
              : [AppColors.deepNavy, AppColors.info],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${RiderQuotaPeriod.label(quota.period)} Collection Quota',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusChip(
                label: quota.achieved
                    ? 'Achieved'
                    : RiderQuotaStatus.label(quota.status),
                color: Colors.white,
                background: Colors.white.withValues(alpha: 0.18),
              ),
            ],
          ),
          SizedBox(height: isWide ? 16 : 14),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(flex: 5, child: amountBlock),
                const SizedBox(width: 32),
                Expanded(flex: 6, child: metricsRow),
              ],
            )
          else ...[
            amountBlock,
            const SizedBox(height: 16),
            metricsRow,
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: quota.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.event_outlined, color: Colors.white70, size: 14),
              const SizedBox(width: 6),
              // `Expanded` + ellipsis: kapag makitid ang screen (o malaki ang
              // font size ng device), liliit ang petsa imbes na umapaw sa
              // gilid — dati `Spacer` lang at puputok ang row.
              Expanded(
                child: Text(
                  '${quota.startDate == null ? '—' : dateFmt.format(quota.startDate!)}'
                  ' – '
                  '${quota.endDate == null ? '—' : dateFmt.format(quota.endDate!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${quota.paymentCount} payment${quota.paymentCount == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          if (quota.isOverTarget) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Collected ${quota.confirmedCollection.toPeso()} — above target. '
                'The full amount is kept; the progress bar is capped at 100%.',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final RiderQuotaPayment payment;

  /// May linya sa ibaba maliban sa huling row — divider sa loob ng section
  /// card, hindi hiwalay na bordered na kahon.
  final bool divider;
  const _PaymentTile({required this.payment, this.divider = false});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, y · h:mm a');
    final meta = [
      if (payment.loanNumber != null && payment.loanNumber!.isNotEmpty)
        payment.loanNumber!,
      if (payment.installmentNumber != null)
        'Installment ${payment.installmentNumber}',
      if (payment.paymentMethod != null && payment.paymentMethod!.isNotEmpty)
        payment.paymentMethod!.toUpperCase(),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: context.cDivider))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.verified_outlined,
                size: 18, color: AppColors.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.amount.toPeso(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.cTextPrimary,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11, color: context.cTextSecondary),
                  ),
              ],
            ),
          ),
          if (payment.paidAt != null)
            Text(
              dateFmt.format(payment.paidAt!),
              style: TextStyle(fontSize: 10, color: context.cTextTertiary),
            ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final RiderQuota quota;
  final bool divider;
  const _HistoryTile({required this.quota, this.divider = false});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, y');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: context.cDivider))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${RiderQuotaPeriod.label(quota.period)} · '
                  '${quota.startDate == null ? '—' : dateFmt.format(quota.startDate!)}'
                  ' – ${quota.endDate == null ? '—' : dateFmt.format(quota.endDate!)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.cTextPrimary,
                  ),
                ),
              ),
              _StatusChip(
                label: quota.achieved
                    ? 'Achieved'
                    : RiderQuotaStatus.label(quota.status),
                color: quota.achieved
                    ? AppColors.success
                    : AppColors.textSecondary,
                background: (quota.achieved
                        ? AppColors.success
                        : AppColors.textSecondary)
                    .withValues(alpha: 0.12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${quota.confirmedCollection.toPeso()} of '
                  '${quota.targetAmount.toPeso()}',
                  style: TextStyle(fontSize: 12, color: context.cTextSecondary),
                ),
              ),
              Text(
                quota.completionPercentage == null
                    ? '—'
                    : '${quota.completionPercentage!.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: riderQuotaProgressColor(
                    quota.completionPercentage,
                    achieved: quota.achieved,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RiderQuotaProgress(
            percent: quota.completionPercentage,
            achieved: quota.achieved,
            showLabel: false,
          ),
        ],
      ),
    );
  }
}

class _NoQuotaCard extends StatelessWidget {
  const _NoQuotaCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_outlined, size: 28, color: context.cTextTertiary),
          const SizedBox(height: 10),
          Text(
            'No quota assigned yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.cTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'When the Head Manager assigns a daily, weekly, or monthly target, '
            'the progress and the verified collections that build it up will '
            'appear here.',
            style: TextStyle(fontSize: 12, color: context.cTextSecondary),
          ),
        ],
      ),
    );
  }
}

/// Seksyon ng pahina bilang isang card: may header (icon, title, subtitle)
/// at divider bago ang mga row. Sa desktop, dalawang card ito na magkatabi;
/// sa mobile, naka-stack — pareho ang itsura, hindi na dalawang layout.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.riderGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: AppColors.riderGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.cTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cTextTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.cDivider),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Walang laman pa ang seksyon — flat na row sa loob ng section card (hindi
/// na border sa loob ng border).
class _SectionEmpty extends StatelessWidget {
  final IconData icon;
  final String message;
  const _SectionEmpty({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.cTextTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: context.cTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  const _StatusChip({
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
