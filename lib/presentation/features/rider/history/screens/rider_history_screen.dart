// ignore_for_file: prefer_const_constructors
// lib/presentation/features/rider/history/screens/rider_history_screen.dart
// Rider History — combined feed ng lahat ng natapos na gawain:
// Collections (completed) / CI Tasks (completed) / Deliveries (completed).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/widgets/layout/mobile_refresh.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
// Isang breakpoint lang ang buong app para sa desktop chrome — dito rin
// sinasalalay ang lapad ng content para kapareho ng dashboard/profile.
import '../../../../shared/widgets/layout/web_scaffold.dart'
    show kDesktopBreakpoint;
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/rider_history_provider.dart';

class RiderHistoryScreen extends ConsumerStatefulWidget {
  const RiderHistoryScreen({super.key});

  @override
  ConsumerState<RiderHistoryScreen> createState() => _RiderHistoryScreenState();
}

class _RiderHistoryScreenState extends ConsumerState<RiderHistoryScreen> {
  static const _navItems = [
    MobileNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        route: RouteConstants.riderDashboard),
    MobileNavItem(
        icon: Icons.delivery_dining_outlined,
        activeIcon: Icons.delivery_dining,
        label: 'Collections',
        route: RouteConstants.riderCollections),
    MobileNavItem(
        icon: Icons.search_outlined,
        activeIcon: Icons.search,
        label: 'CI Tasks',
        route: RouteConstants.riderCi),
    // Ika-4 na item — bago ang Profile.
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderHistoryProvider);
    // Desktop: naka-center at may max na lapad ang feed (kapareho ng rider
    // dashboard/profile). Sa mobile, buong lapad pa rin gaya dati.
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    final hPad = isDesktop ? 28.0 : 16.0;
    final bottomPad = isDesktop ? 40.0 : 100.0;
    final listPadding =
        EdgeInsets.fromLTRB(hPad, isDesktop ? 20 : 16, hPad, bottomPad);
    // Pinagsama-sama ang lahat ng natapos na gawain sa ISANG listahan,
    // pinakabago muna. Ang uri nito (Collection / CI Task / Delivery) ay nasa
    // card mismo — kaya walang tabs sa header.
    final entries = <_HistoryEntry>[
      ...state.collections.map((c) => _HistoryEntry(
            c.completedAt ?? c.collectionSchedule ?? c.createdAt,
            _CollectionHistoryCard(item: c),
          )),
      ...state.ciTasks.map((ci) => _HistoryEntry(
            ci.completedAt ?? ci.reviewedAt ?? ci.createdAt,
            _CiHistoryCard(item: ci),
          )),
      ...state.deliveries.map((d) => _HistoryEntry(
            d.disbursedAt ?? d.deliveryDate ?? d.createdAt,
            _DeliveryHistoryCard(item: d),
          )),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return MobileScaffold(
      title: 'History',
      accentColor: AppColors.riderGreen,
      navItems: _navItems,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            children: [
              _MonthFilterBar(
                selectedMonth: state.selectedMonth,
                margin: EdgeInsets.fromLTRB(
                    hPad, isDesktop ? 20 : 12, hPad, 4),
                onChanged: (m) =>
                    ref.read(riderHistoryProvider.notifier).setMonth(m),
                onClear: () =>
                    ref.read(riderHistoryProvider.notifier).clearFilter(),
              ),
              if (state.error != null)
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.fromLTRB(hPad, 10, hPad, 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(state.error!,
                      style:
                          TextStyle(fontSize: 12, color: AppColors.error)),
                ),
              Expanded(
                child: _HistoryList<_HistoryEntry>(
                  items: entries,
                  isLoading: state.isLoading,
                  padding: listPadding,
                  // Silent load: hindi na kailangang mag-flash ng shimmer
                  // habang nakabitin ang pull-down spinner.
                  onRefresh: () => ref
                      .read(riderHistoryProvider.notifier)
                      .load(silent: true),
                  emptyText: 'No history yet',
                  itemBuilder: (e) => e.card,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Buwanang filter — parehong pattern sa rider dashboard filter bar.
class _MonthFilterBar extends StatelessWidget {
  final String? selectedMonth;
  final ValueChanged<String?> onChanged;
  final VoidCallback onClear;

  /// Panlabas na margin ng bar — iba ang padding ng desktop (28) at mobile
  /// (16) para pantay ito sa listahan sa ilalim.
  final EdgeInsetsGeometry margin;

  const _MonthFilterBar({
    required this.selectedMonth,
    required this.onChanged,
    required this.onClear,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 4),
  });

  @override
  Widget build(BuildContext context) {
    final hasFilter = selectedMonth != null;
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined,
              size: 18, color: AppColors.riderGreen),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: selectedMonth,
                hint: Text('All time',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.cTextSecondary)),
                isDense: true,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.cTextPrimary),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All time')),
                  ...RiderHistoryNotifier.availableMonths().map((m) =>
                      DropdownMenuItem<String?>(
                          value: m,
                          child:
                              Text(RiderHistoryNotifier.monthLabel(m)))),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
          if (hasFilter)
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded,
                    size: 16, color: context.cTextSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loading / empty / list states para sa isang tab.
class _HistoryList<T> extends StatelessWidget {
  final List<T> items;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final String emptyText;
  final Widget Function(T item) itemBuilder;

  /// Padding ng listahan — mas malaki sa desktop at walang 100px na puwang
  /// para sa floating bottom nav (wala iyon sa desktop shell).
  final EdgeInsetsGeometry padding;

  const _HistoryList({
    required this.items,
    required this.isLoading,
    required this.onRefresh,
    required this.emptyText,
    required this.itemBuilder,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) {
      return ListView.builder(
        padding: padding,
        itemCount: 5,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: ShimmerLoader(height: 104, borderRadius: 16),
        ),
      );
    }
    if (items.isEmpty) {
      // Naka-scroll: kailangan ito para gumana ang pull-to-refresh kahit
      // walang laman ang history.
      return MobileRefresh(
        color: AppColors.riderGreen,
        fill: true,
        onRefresh: onRefresh,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.riderGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.history_rounded,
                    size: 38, color: AppColors.riderGreen),
              ),
              const SizedBox(height: 14),
              Text(emptyText,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.cTextPrimary)),
              const SizedBox(height: 6),
              Text('Finished tasks will show up here.',
                  style: TextStyle(fontSize: 12.5, color: context.cTextSecondary)),
            ],
          ),
        ),
      );
    }
    return MobileRefresh(
      color: AppColors.riderGreen,
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: items.length,
        itemBuilder: (_, i) => itemBuilder(items[i]),
      ),
    );
  }
}

/// Isang entry sa pinagsamang history: ang card + ang petsa nito, para
/// mapagsunod-sunod lahat ng uri (collection / CI / delivery) nang pinakabago
/// muna sa isang listahan.
class _HistoryEntry {
  final DateTime date;
  final Widget card;
  const _HistoryEntry(this.date, this.card);
}

// ─────────────────────────────────────────────────────────────────────────────
// Cards
// ─────────────────────────────────────────────────────────────────────────────
class _HistoryCard extends StatelessWidget {
  final String keyId;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String trailingTitle;
  final String trailingCaption;
  final VoidCallback? onTap;

  /// Uri ng gawain na nakalagay sa card (hal. 'Collection', 'CI Task',
  /// 'Cash Delivery', o 'CI Approved' kapag na-review na ng staff) — ito ang
  /// pumapalit sa dati na tabs sa header.
  final String typeLabel;

  const _HistoryCard({
    required this.keyId,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.trailingTitle,
    required this.trailingCaption,
    required this.typeLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Sa dark mode, mas maliwanag ang tint/foreground para hindi mawala ang
    // icon at type pill sa ibabaw ng dark card.
    final fg = context.isDarkMode
        ? Color.lerp(accent, Colors.white, 0.55)!
        : accent;
    return GestureDetector(
      key: ValueKey(keyId),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cBorder),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: fg, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: context.cTextPrimary)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: context.cTextSecondary)),
                    ],
                  ),
                ),
                // Uri ng gawain — nasa card na, kaya walang tabs sa header.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: fg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: context.cDivider),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(trailingTitle,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: context.cTextPrimary)),
                const Spacer(),
                Icon(Icons.event_rounded,
                    size: 13, color: context.cTextTertiary),
                const SizedBox(width: 4),
                Text(trailingCaption,
                    style: TextStyle(
                        fontSize: 11.5, color: context.cTextSecondary)),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: context.cTextTertiary),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionHistoryCard extends StatelessWidget {
  final CollectionAssignmentModel item;
  const _CollectionHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final peso = NumberFormat('#,##0.00', 'en_PH');
    // Nakolekta kung meron; kung wala pa, ang HININGI ng lender
    // (`requested_amount`) — hindi ang default na installment due.
    final amount = item.collectibleAmount;
    final date = item.completedAt ?? item.collectionSchedule ?? item.createdAt;
    // Kasama na ang failed/"uncollected" collections sa history — kulay pula
    // at "Uncollected" ang label para hindi ito mapagkamalang nakolekta.
    final uncollected = item.status == 'failed';
    return _HistoryCard(
      keyId: 'coll_${item.id}',
      icon:
          uncollected ? Icons.error_outline_rounded : Icons.payments_outlined,
      accent: uncollected ? AppColors.statusRejected : AppColors.riderGreen,
      title: item.lenderName.isEmpty ? 'Lender' : item.lenderName,
      subtitle: 'Loan #${item.loanNumber.isEmpty ? '—' : item.loanNumber}',
      trailingTitle: '₱${peso.format(amount)}',
      trailingCaption: date.toDateString(),
      typeLabel: uncollected ? 'Uncollected' : 'Collection',
      onTap: () => context.push('${RouteConstants.riderCollections}/${item.id}'),
    );
  }
}

class _CiHistoryCard extends StatelessWidget {
  final CreditInvestigationModel item;
  const _CiHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final date = item.completedAt ?? item.reviewedAt ?? item.createdAt;
    return _HistoryCard(
      keyId: 'ci_${item.id}',
      icon: Icons.search_outlined,
      accent: AppColors.lenderBlue,
      title: item.borrowerName.isEmpty ? 'Lender' : item.borrowerName,
      subtitle: 'Loan #${item.loanNumber.isEmpty ? '—' : item.loanNumber}',
      trailingTitle: (item.reportSummary ?? '').trim().isEmpty
          ? 'No report'
          : 'Report submitted',
      trailingCaption: date.toDateString(),
      typeLabel: switch (item.status) {
        'approved' => 'CI Approved',
        'rejected' => 'CI Rejected',
        _ => 'CI Task',
      },
      onTap: () => context.push('${RouteConstants.riderCi}/${item.id}'),
    );
  }
}

class _DeliveryHistoryCard extends StatelessWidget {
  final DisbursementModel item;
  const _DeliveryHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final peso = NumberFormat('#,##0.00', 'en_PH');
    final date = item.disbursedAt ?? item.deliveryDate ?? item.createdAt;
    return _HistoryCard(
      keyId: 'disb_${item.id}',
      icon: Icons.delivery_dining_outlined,
      accent: AppColors.warning,
      title: item.lenderName.isEmpty ? 'Lender' : item.lenderName,
      subtitle:
          'Loan #${item.loanNumber.isEmpty ? '—' : item.loanNumber} • ${item.methodLabel}',
      trailingTitle: '₱${peso.format(item.amount)}',
      trailingCaption: date.toDateString(),
      typeLabel: 'Cash Delivery',
    );
  }
}
