// lib/presentation/features/head_manager/disbursements/screens/hm_disbursement_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/search_results_chip.dart';
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
  DateTimeRange? _dateRange;

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    ref.read(hmDisbursementProvider.notifier).setDateRange(
          r == null ? null : SearchDateFilter.fromParam(r.start),
          r == null ? null : SearchDateFilter.toParam(r.end),
        );
  }

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
      child: ResponsiveSearchToolbar(
        searchField: TextField(
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
        trailing: [
          SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
          SearchResultsChip(count: state.disbursements.length),
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
      child: ResponsiveListCard(
        minTableWidth: 880,
        variant: ResponsiveListVariant.card,
        headerTextStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary),
        columns: const [
          ResponsiveCol('Loan #', flex: 2),
          ResponsiveCol('Lender', flex: 3),
          ResponsiveCol('Method', flex: 2),
          ResponsiveCol('Amount', flex: 2),
          ResponsiveCol('Status', flex: 2),
          ResponsiveCol('Date', flex: 2),
        ],
        actionsCol: const ResponsiveActionsCol(
            label: 'Actions', width: 80, alignment: Alignment.centerRight, alignEnd: true),
        rowBorder: const Border(bottom: BorderSide(color: AppColors.divider)),
        rows: items.map((d) => _buildRow(context, d)).toList(),
      ),
    );
  }

  ResponsiveRow _buildRow(BuildContext context, DisbursementModel d) {
    return ResponsiveRow(
      cells: [
        Text(d.loanNumber,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.deepNavy)),
        Text(d.lenderName, style: const TextStyle(fontSize: 13)),
        _methodChip(d.disbursementMethod),
        Text('₱${d.amount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        StatusBadge(status: d.status),
        Text(DateFormat('MMM d, y h:mm a').format(d.createdAt),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
      actions: Tooltip(
        message: 'View',
        child: InkWell(
          onTap: () => context.go('/hm/disbursements/${d.id}'),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.deepNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.deepNavy.withValues(alpha: 0.14)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined, size: 14, color: AppColors.deepNavy),
                SizedBox(width: 4),
                Text('View',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepNavy)),
              ],
            ),
          ),
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
      'rider_delivery' => AppColors.lenderBlue,
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
