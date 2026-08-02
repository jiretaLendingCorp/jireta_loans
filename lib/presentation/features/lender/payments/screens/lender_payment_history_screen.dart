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
import '../providers/lender_payment_provider.dart';
import '../../../../../data/models/payment_model.dart';

const _lenderNavItems = [
  MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard),
  MobileNavItem(
      icon: Icons.account_balance_outlined,
      activeIcon: Icons.account_balance,
      label: 'My Loan',
      route: RouteConstants.lenderLoans),
  MobileNavItem(
      icon: Icons.payment_outlined,
      activeIcon: Icons.payment,
      label: 'Payments',
      route: RouteConstants.lenderPayments),
  MobileNavItem(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      label: 'Alerts',
      route: RouteConstants.lenderNotifications),
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
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(lenderPaymentProvider.notifier).loadPaymentHistory());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderPaymentProvider);

    return MobileScaffold(
      title: 'Payment History',
      accentColor: AppColors.lenderPurple,
      navItems: _lenderNavItems,
      showBackButton: true,
      body: state.isLoading
          ? const ShimmerLoader()
          : state.error != null
              ? Center(child: Text('Error: ${state.error}'))
              : state.payments.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.receipt_long_outlined,
                      title: 'No Payment History',
                      subtitle:
                          'Your payment transactions will appear here once you start making payments.',
                    )
                  : RefreshIndicator(
                      color: AppColors.lenderPurple,
                      onRefresh: () => ref
                          .read(lenderPaymentProvider.notifier)
                          .loadPaymentHistory(),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: state.payments.length,
                        itemBuilder: (ctx, i) =>
                            _PaymentCard(item: state.payments[i]),
                      ),
                    ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final PaymentModel item;
  const _PaymentCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final paymentId = item.id;
    final amount = item.amount;
    final method = item.method;
    final status = item.status;
    final referenceNum = item.referenceNumber;

    final methodIcon = method == 'gcash'
        ? Icons.phone_android
        : method == 'office_cash'
            ? Icons.business
            : Icons.delivery_dining;
    final methodLabel = item.methodLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: InkWell(
        onTap: () => context.push(
            RouteConstants.lenderPaymentReceipt.replaceAll(':id', paymentId)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.lenderPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(methodIcon, color: AppColors.lenderPurple, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(methodLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    if (referenceNum != null)
                      Text('Ref: $referenceNum',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textTertiary)),
                    Text(item.createdAt.toShortDate,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(amount.toCurrency,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  StatusBadge(status: status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
