// lib/presentation/features/rider/disbursements/screens/rider_disbursement_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/rider_disbursement_provider.dart';

class RiderDisbursementListScreen extends ConsumerStatefulWidget {
  const RiderDisbursementListScreen({super.key});

  @override
  ConsumerState<RiderDisbursementListScreen> createState() =>
      _RiderDisbursementListScreenState();
}

class _RiderDisbursementListScreenState
    extends ConsumerState<RiderDisbursementListScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderDisbursementProvider);

    return MobileScaffold(
      title: 'Cash Deliveries',
      accentColor: AppColors.riderGreen,
      showBottomNav: true,
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
          icon: Icons.delivery_dining_outlined,
          activeIcon: Icons.delivery_dining,
          label: 'Deliveries',
          route: RouteConstants.riderDisbursements,
        ),
        MobileNavItem(
          icon: Icons.person_outline,
          activeIcon: Icons.person,
          label: 'Profile',
          route: RouteConstants.riderProfile,
        ),
      ],
      body: state.isLoading
          ? ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: 5,
              itemBuilder: (_, __) => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: ShimmerLoader(height: 120, borderRadius: 16),
              ),
            )
          : state.disbursements.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: AppColors.riderGreen,
                  onRefresh: () =>
                      ref.read(riderDisbursementProvider.notifier).refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: state.disbursements.length,
                    itemBuilder: (_, i) =>
                        _buildCard(context, state.disbursements[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.riderGreen.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.delivery_dining,
                size: 44, color: AppColors.riderGreen),
          ),
          const SizedBox(height: 16),
          const Text(
            'No cash delivery assignments',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'When the office assigns you a loan disbursement, it will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, DisbursementModel disbursement) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final delivery = disbursement.deliveryDate;
    return Container(
      key: ValueKey(disbursement.id),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.riderGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.payments_outlined,
                    color: AppColors.riderGreen, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      disbursement.loanNumber.isNotEmpty
                          ? 'Loan ${disbursement.loanNumber}'
                          : 'Cash Delivery',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      disbursement.lenderName.isEmpty
                          ? 'Lender'
                          : 'To: ${disbursement.lenderName}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'PENDING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '₱${fmt.format(disbursement.amount)}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (delivery != null)
                Text(
                  'Deliver by: ${delivery.month}/${delivery.day}/${delivery.year}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                RouteConstants.riderDisbursementUploadProof.replaceFirst(
                    ':id', disbursement.id),
              ),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Upload Delivery Proof'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.riderGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
