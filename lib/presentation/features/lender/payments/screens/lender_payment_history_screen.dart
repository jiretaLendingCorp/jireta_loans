// lib/presentation/features/lender/payments/screens/lender_payment_history_screen.dart
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
import '../../../../shared/widgets/tables/table_pagination.dart';
import '../providers/lender_payment_provider.dart';
import '../../../../../data/models/payment_model.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
  MobileNavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'History',
      route: RouteConstants.lenderPaymentHistory),

  MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile),
];

class LenderPaymentHistoryScreen extends ConsumerStatefulWidget {
  const LenderPaymentHistoryScreen({super.key});

  @override
  ConsumerState<LenderPaymentHistoryScreen> createState() => _State();
}

class _State extends ConsumerState<LenderPaymentHistoryScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(lenderPaymentProvider.notifier).loadPaymentHistory());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderPaymentProvider);
    final notifier = ref.read(lenderPaymentProvider.notifier);
    final filtered = state.filteredPayments;

    return MobileScaffold(
      title: 'Payment History',
      accentColor: AppColors.lenderBlue,
      navItems: _lenderNavItems,
      showBackButton: true,
      appBarActions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          onPressed: () => notifier.loadPaymentHistory(),
          tooltip: 'Refresh',
        ),
      ],
      body: Column(
        children: [
          // Search + filters (simplified: only All / Office / Rider)
          _FilterBar(
            state: state,
            searchCtrl: _searchCtrl,
            onMethod: notifier.setMethodFilter,
            onSearch: notifier.setSearch,
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.error != null
                    ? Center(
                        child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
                            const SizedBox(height: 12),
                            Text('Error: ${state.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.lenderBlue),
                              onPressed: () => notifier.loadPaymentHistory(),
                              icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                              label: const Text('Retry', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      ))
                    : filtered.isEmpty
                        ? state.payments.isEmpty
                            ? const EmptyStateWidget(
                                icon: Icons.receipt_long_outlined,
                                title: 'No Payment History',
                                subtitle: 'Your payment transactions will appear here once you start making payments. Tap Pay on your active loan to start.',
                              )
                            : _EmptyFiltered(onClear: () {
                                _searchCtrl.clear();
                                notifier.setSearch('');
                                notifier.setMethodFilter('all');
                              })
                        : RefreshIndicator(
                            color: AppColors.lenderBlue,
                            onRefresh: () => notifier.refreshHistory(),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) => _PaymentCard(
                                  key: ValueKey(filtered[i].id), item: filtered[i]),
                            ),
                          ),
          ),
          if (state.totalPages > 1)
            TablePagination(
              currentPage: state.currentPage,
              totalPages: state.totalPages,
              totalCount: state.totalCount,
              onPageChange: (p) => notifier.loadPayments(page: p),
            ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final LenderPaymentState state;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onMethod;
  final ValueChanged<String> onSearch;
  const _FilterBar({required this.state, required this.searchCtrl, required this.onMethod, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search',
              hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textTertiary),
              suffixIcon: searchCtrl.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () { searchCtrl.clear(); onSearch(''); })
                  : null,
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: onSearch,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _Pill(label: 'All', selected: state.methodFilter == 'all', color: AppColors.deepNavy, onTap: () => onMethod('all')),
              const SizedBox(width: 6),
              _Pill(label: 'Office', selected: state.methodFilter == 'office_cash', onTap: () => onMethod('office_cash')),
              const SizedBox(width: 6),
              _Pill(label: 'Rider', selected: state.methodFilter == 'rider_collection', onTap: () => onMethod('rider_collection')),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.selected, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.lenderBlue;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : AppColors.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}

class _EmptyFiltered extends StatelessWidget {
  final VoidCallback onClear;
  const _EmptyFiltered({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.search_off_rounded, size: 28, color: AppColors.textTertiary)),
          const SizedBox(height: 14),
          const Text('No matches', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('Try adjusting status, method or search', style: TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onClear, child: const Text('Clear filters')),
        ]),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final PaymentModel item;
  const _PaymentCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final paymentId = item.id;
    final amount = item.amount;
    final method = item.method;
    final status = item.status;
    final referenceNum = item.referenceNumber;
    final loanNumber = item.loanNumber.isNotEmpty ? item.loanNumber : (item.loan?['loan_number'] ?? '');

    final methodIcon = method.contains('gcash')
        ? Icons.phone_android
        : method == 'office_cash' || method == 'cash'
            ? Icons.storefront_rounded
            : Icons.delivery_dining_rounded;
    final methodLabel = item.methodLabel;
    final isVerified = status == 'verified';
    final isReversed = status == 'reversed';
    final accent = isVerified ? AppColors.success : isReversed ? AppColors.error : status == 'pending' ? AppColors.warning : AppColors.lenderBlue;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: InkWell(
        onTap: () => context.push(RouteConstants.lenderPaymentReceipt.replaceAll(':id', paymentId)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10), border: Border.all(color: accent.withValues(alpha: 0.15))),
                    child: Icon(methodIcon, color: accent, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(methodLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                        const SizedBox(width: 6),
                        StatusBadge(status: status),
                      ]),
                      const SizedBox(height: 3),
                      if (loanNumber.isNotEmpty) Text('Loan: $loanNumber', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      if (referenceNum != null && referenceNum.isNotEmpty) Text('Ref: $referenceNum', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                      Text(item.createdAt.toShortDate, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(amount.toCurrency, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isReversed ? AppColors.error : AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6), border: Border.all(color: accent.withValues(alpha: 0.18))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(isVerified ? Icons.check_circle_rounded : isReversed ? Icons.undo_rounded : Icons.schedule_rounded, size: 12, color: accent),
                        const SizedBox(width: 4),
                        Text(item.statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent)),
                      ]),
                    ),
                  ]),
                ],
              ),
              if (item.loan != null && (item.lenderName.isNotEmpty || loanNumber.isNotEmpty)) ...[
                const SizedBox(height: 10),
                const Divider(height: 1, color: AppColors.divider),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(item.lenderName.isNotEmpty ? 'Paid for ${item.lenderName}' : 'Loan payment', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                  const Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.textTertiary),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
