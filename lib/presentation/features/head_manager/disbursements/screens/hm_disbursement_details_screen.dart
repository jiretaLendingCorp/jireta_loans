// lib/presentation/features/head_manager/disbursements/screens/hm_disbursement_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../data/datasources/remote/disbursement_remote_datasource.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/app_card.dart';

final _disbursementDetailProvider =
    FutureProvider.family<DisbursementModel?, String>((ref, id) async {
  final ds = sl<DisbursementRemoteDataSource>();
  return ds.getDisbursementDetail(id);
});

class HmDisbursementDetailsScreen extends ConsumerWidget {
  final String disbursementId;
  const HmDisbursementDetailsScreen({super.key, required this.disbursementId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_disbursementDetailProvider(disbursementId));
    return WebScaffold(
      title: 'Disbursement Details',
      body: async.when(
        loading: () => const Center(child: ShimmerLoader()),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (d) => d == null
            ? const Center(child: Text('Disbursement not found'))
            : _buildBody(context, d),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DisbursementModel d) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(d),
          const SizedBox(height: 20),
          _buildInfoCard(d),
          const SizedBox(height: 20),
          _buildMethodCard(d),
        ],
      ),
    );
  }

  Widget _buildHeader(DisbursementModel d) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Disbursement Record',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy)),
                const SizedBox(height: 4),
                Text('Loan #${d.loanId}',
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          StatusBadge(status: d.status),
        ],
      );

  Widget _buildInfoCard(DisbursementModel d) => AppCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Disbursement Information',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: AppColors.deepNavy)),
              const Divider(height: 24),
              _row('Amount', d.amount.toCurrency),
              _row('Method', d.method.toUpperCase().replaceAll('_', ' ')),
              _row('Status', d.status.toUpperCase()),
              if (d.reference.isNotEmpty) _row('Reference', d.reference),
              _row('Date',
                  DateFormat('MMM dd, yyyy hh:mm a').format(d.createdAt)),
            ],
          ),
        ),
      );

  Widget _buildMethodCard(DisbursementModel d) {
    if (d.method == 'gcash') {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('GCash Details',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: AppColors.deepNavy)),
              const Divider(height: 24),
              _row('Xendit Disbursement ID', d.xenditDisbursementId ?? 'N/A'),
              _row('Xendit Status', d.xenditStatus ?? 'N/A'),
              if (d.disbursedAt != null)
                _row('Disbursed At',
                    DateFormat('MMM dd, yyyy hh:mm a').format(d.disbursedAt!)),
            ],
          ),
        ),
      );
    }
    if (d.method == 'office_cash') {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Office Cash Release',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: AppColors.deepNavy)),
              const Divider(height: 24),
              _row('Disbursed By', d.disbursedBy ?? 'N/A'),
              if (d.disbursedAt != null)
                _row('Release Date',
                    DateFormat('MMM dd, yyyy hh:mm a').format(d.disbursedAt!)),
            ],
          ),
        ),
      );
    }
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rider Delivery Details',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.deepNavy)),
            const Divider(height: 24),
            _row('Assigned Rider', d.disbursedBy ?? 'N/A'),
            _row('Status', d.status),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 180,
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary))),
          ],
        ),
      );
}
