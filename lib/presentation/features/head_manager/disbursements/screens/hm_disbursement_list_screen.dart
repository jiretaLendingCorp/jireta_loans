// lib/presentation/features/head_manager/disbursements/screens/hm_disbursement_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/hm_disbursement_provider.dart';

class HmDisbursementListScreen extends ConsumerStatefulWidget {
  const HmDisbursementListScreen({super.key});

  @override
  ConsumerState<HmDisbursementListScreen> createState() =>
      _HmDisbursementListScreenState();
}

class _HmDisbursementListScreenState
    extends ConsumerState<HmDisbursementListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmDisbursementProvider);

    return WebScaffold(
      title: 'Disbursements',
      body: Column(
        children: [
          _buildFilters(state),
          Expanded(
            child: state.isLoading
                ? _buildShimmer()
                : state.disbursements.isEmpty
                    ? const EmptyStateWidget(
                        title: 'No Disbursements',
                        message: 'Loan disbursements will appear here',
                        icon: Icons.account_balance_wallet_outlined,
                      )
                    : _buildTable(context, state.disbursements),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(HmDisbursementState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search loan number or lender...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) =>
                  ref.read(hmDisbursementProvider.notifier).setSearch(v),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: state.methodFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All Methods')),
              DropdownMenuItem(value: 'gcash', child: Text('GCash')),
              DropdownMenuItem(
                  value: 'office_cash', child: Text('Office Cash')),
              DropdownMenuItem(
                  value: 'rider_delivery', child: Text('Rider Delivery')),
            ],
            onChanged: (v) =>
                ref.read(hmDisbursementProvider.notifier).setMethod(v!),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: state.statusFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All Status')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
              DropdownMenuItem(value: 'failed', child: Text('Failed')),
            ],
            onChanged: (v) =>
                ref.read(hmDisbursementProvider.notifier).setStatus(v!),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, List<DisbursementModel> items) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          children: [
            _buildHeader(),
            ...items.map((d) => _buildRow(context, d)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const style = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('Loan #', style: style)),
          Expanded(flex: 3, child: Text('Lender', style: style)),
          Expanded(flex: 2, child: Text('Method', style: style)),
          Expanded(flex: 2, child: Text('Amount', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
          Expanded(flex: 2, child: Text('Date', style: style)),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, DisbursementModel d) {
    return InkWell(
      onTap: () => context.go('/hm/disbursements/${d.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
                flex: 2,
                child: Text(d.loanNumber,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.deepNavy))),
            Expanded(
                flex: 3,
                child:
                    Text(d.lenderName, style: const TextStyle(fontSize: 13))),
            Expanded(
                flex: 2, child: _methodChip(d.disbursementMethod)),
            Expanded(
                flex: 2,
                child: Text('₱${d.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13))),
            Expanded(flex: 2, child: StatusBadge(status: d.status)),
            Expanded(
                flex: 2,
                child: Text(
                    DateFormat('MMM d, y').format(d.createdAt),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary))),
          ],
        ),
      ),
    );
  }

  Widget _methodChip(String method) {
    final label = switch (method) {
      'gcash' => 'GCash',
      'office_cash' => 'Office Cash',
      'rider_delivery' => 'Rider',
      _ => method,
    };
    final color = switch (method) {
      'gcash' => AppColors.info,
      'office_cash' => AppColors.success,
      'rider_delivery' => AppColors.lenderPurple,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
          children: List.generate(
              6,
              (i) => const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: ShimmerLoader(height: 56),
                  ))),
    );
  }
}
