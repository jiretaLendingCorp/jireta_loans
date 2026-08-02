// lib/presentation/features/employee/payments/screens/emp_payment_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/tables/table_filter_bar.dart';
import '../../../../shared/widgets/tables/table_pagination.dart';
import '../providers/emp_payment_provider.dart';
import '../widgets/record_office_payment_modal.dart';

class EmpPaymentListScreen extends ConsumerStatefulWidget {
  const EmpPaymentListScreen({super.key});

  @override
  ConsumerState<EmpPaymentListScreen> createState() =>
      _EmpPaymentListScreenState();
}

class _EmpPaymentListScreenState extends ConsumerState<EmpPaymentListScreen> {
  final _searchCtrl = TextEditingController();
  String? _methodFilter;
  String? _statusFilter;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(empPaymentListProvider.notifier).loadList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empPaymentListProvider);
    final items = state.valueOrNull?['items'] as List? ?? [];
    final total = state.valueOrNull?['total'] as int? ?? 0;
    final totalPages = (total / 20).ceil();

    return WebScaffold(
      title: 'Payments',
      actions: [
        ElevatedButton.icon(
          onPressed: () => _showRecordModal(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Record Office Payment'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black87,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => ref.read(empPaymentListProvider.notifier).loadList(
              method: _methodFilter, status: _statusFilter, page: _currentPage),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
        ),
      ],
      body: Column(
        children: [
          buildFilterBar(
            searchController: _searchCtrl,
            searchHint: 'Search by loan# or lender...',
            filters: [
              (
                label: 'Method',
                value: _methodFilter ?? 'all',
                options: ['all', 'gcash', 'office_cash', 'rider_collection'],
                onChanged: (v) {
                  setState(() => _methodFilter = v == 'all' ? null : v);
                  ref.read(empPaymentListProvider.notifier).loadList(
                      method: _methodFilter, status: _statusFilter, page: 1);
                },
              ),
              (
                label: 'Status',
                value: _statusFilter ?? 'all',
                options: ['all', 'pending', 'verified', 'reversed'],
                onChanged: (v) {
                  setState(() => _statusFilter = v == 'all' ? null : v);
                  ref.read(empPaymentListProvider.notifier).loadList(
                      method: _methodFilter, status: _statusFilter, page: 1);
                },
              ),
            ],
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : items.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.payment_outlined,
                        title: 'No payments found',
                        subtitle: 'Payment records will appear here.',
                      )
                    : _PaymentListView(items: items),
          ),
          if (totalPages > 1)
            TablePagination(
              currentPage: _currentPage,
              totalPages: totalPages,
              totalCount: total,
              onPageChange: (p) {
                setState(() => _currentPage = p);
                ref.read(empPaymentListProvider.notifier).loadList(
                    method: _methodFilter, status: _statusFilter, page: p);
              },
            ),
        ],
      ),
    );
  }

  void _showRecordModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => RecordOfficePaymentModal(
        onRecorded: () {
          ref.read(empPaymentListProvider.notifier).loadList(
              method: _methodFilter, status: _statusFilter, page: _currentPage);
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment recorded successfully.')));
        },
      ),
    );
  }
}

class _PaymentListView extends StatelessWidget {
  final List items;
  const _PaymentListView({required this.items});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final p = items[i] as Map<String, dynamic>;
        final id = p['id'] as String? ?? '';
        final loanNumber = p['loan_number'] as String? ?? '-';
        final lenderName = p['lender_name'] as String? ?? '-';
        final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final method = p['payment_method'] as String? ?? '-';
        final status = p['status'] as String? ?? '-';
        final date = p['created_at'] as String? ?? '-';

        return Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.go(
              RouteConstants.empPaymentDetails.replaceFirst(':id', id),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.deepNavy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_outlined,
                        color: AppColors.deepNavy, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(loanNumber,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13)),
                            const SizedBox(width: 8),
                            StatusBadge(status: status),
                          ],
                        ),
                        Text(lenderName,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                        Text('${_methodLabel(method)} • $date',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₱${fmt.format(amount)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.deepNavy)),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textTertiary, size: 18),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'gcash':
        return 'GCash';
      case 'office_cash':
        return 'Office Cash';
      case 'rider_collection':
        return 'Rider Collection';
      default:
        return m;
    }
  }
}
