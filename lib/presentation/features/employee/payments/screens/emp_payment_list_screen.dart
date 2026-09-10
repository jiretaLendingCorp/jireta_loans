// lib/presentation/features/employee/payments/screens/emp_payment_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import 'package:intl/intl.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';
import '../providers/emp_payment_provider.dart';

class EmpPaymentListScreen extends ConsumerStatefulWidget {
  const EmpPaymentListScreen({super.key});

  @override
  ConsumerState<EmpPaymentListScreen> createState() => _EmpPaymentListScreenState();
}

class _EmpPaymentListScreenState extends ConsumerState<EmpPaymentListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _tabs = [
    ('all', 'All'),
    ('gcash', 'GCash'),
    ('office_cash', 'Office'),
    ('rider_collection', 'Rider Collection')
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final tab = _tabs[_tabController.index].$1;
    ref.read(empPaymentListProvider.notifier).fetch(method: tab == 'all' ? null : tab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empPaymentListProvider);
    return WebScaffold(
      title: 'Payments',
      actions: [
        IconButton(
            onPressed: () => ref.read(empPaymentListProvider.notifier).fetch(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh'),
        const SizedBox(width: 12),
      ],
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.deepNavy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.payments.isEmpty
                    ? _buildEmpty()
                    : _buildTable(state),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(EmpPaymentState state) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ResponsiveListCard(
        minTableWidth: 860,
        variant: ResponsiveListVariant.card,
        headerTextStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: AppColors.textSecondary),
        columns: const [
          ResponsiveCol('LENDER', flex: 3),
          ResponsiveCol('LOAN #', flex: 2),
          ResponsiveCol('AMOUNT', flex: 2),
          ResponsiveCol('METHOD', flex: 2),
          ResponsiveCol('DATE', flex: 2),
          ResponsiveCol('STATUS', flex: 2),
        ],
        actionsCol: const ResponsiveActionsCol(label: '', flex: 1),
        rows: state.payments.map((p) => _buildRow(p, fmt)).toList(),
      ),
    );
  }

  ResponsiveRow _buildRow(Map<String, dynamic> p, NumberFormat fmt) {
    final lender = p['lender'] as Map<String, dynamic>? ?? {};
    final loan = p['loan'] as Map<String, dynamic>? ?? {};
    final loanNumberFlat = p['loan_number'] as String? ?? p['loan']?['loan_number'] as String?;
    final displayLoan = loanNumberFlat ?? loan['loan_number'] as String? ?? '-';
    final flatLenderName = p['lender_name'] != null ? p['lender_name'] as String : null;
    final resolvedLender = flatLenderName != null && flatLenderName.isNotEmpty
        ? flatLenderName
        : ('${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim().isEmpty
            ? '-'
            : '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim());
    // Use resolved values
    final status = p['status'] as String? ?? '-';
    final method = p['payment_method'] as String? ?? p['method'] as String? ?? '-';
    final statusColor = status == 'verified'
        ? AppColors.success
        : status == 'pending'
            ? AppColors.warning
            : AppColors.error;
    return ResponsiveRow(
      onTap: () {
        final id = p['id'] as String? ?? '';
        if (id.isNotEmpty) context.go(RouteConstants.empPaymentDetails.replaceFirst(':id', id));
      },
      cells: [
        Text(resolvedLender.isEmpty ? '-' : resolvedLender,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        Text(displayLoan.isEmpty ? '-' : displayLoan, style: const TextStyle(fontSize: 13)),
        Text('₱${fmt.format(p['amount'] ?? 0)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        _buildMethodBadge(method),
        Text(_formatDate(p['created_at']),
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration:
              BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
          child: Text(_capitalize(status),
              style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500)),
        ),
      ],
      actions: status == 'verified'
          ? Tooltip(
              message: 'Reverse Payment',
              child: IconButton(
                onPressed: () => _confirmReverse(p['id'] as String? ?? ''),
                icon: const Icon(Icons.undo, size: 18, color: AppColors.error),
              ),
            )
          : null,
    );
  }

  Widget _buildMethodBadge(String method) {
    Color c;
    switch (method) {
      case 'gcash':
        c = AppColors.lenderBlue;
        break;
      case 'office_cash':
      case 'cash':
        c = AppColors.success;
        break;
      case 'rider_collection':
        c = AppColors.riderGreen;
        break;
      default:
        c = AppColors.info;
    }
    String label;
    switch (method) {
      case 'gcash':
      case 'gcash_xendit':
        label = 'GCash';
        break;
      case 'office_cash':
      case 'cash':
        label = 'Office';
        break;
      case 'rider_collection':
        label = 'Rider Collection';
        break;
      default:
        label = _capitalize(method.replaceAll('_', ' '));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildEmpty() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined, size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text('No payments found', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          ],
        ),
      );

  Future<void> _confirmReverse(String paymentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reverse Payment'),
        content: const Text('Are you sure you want to reverse this payment? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Reverse')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final ok = await ref.read(empPaymentListProvider.notifier).reversePayment(paymentId);
      if (mounted) {
        context.showSnackBarAsToast(
          SnackBar(
              content: Text(ok ? 'Payment reversed' : 'Failed to reverse payment'),
              backgroundColor: ok ? AppColors.success : AppColors.error),
        );
      }
    }
  }

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    final dt = parseManila(d);
    if (dt == null) return d.toString();
    return DateFormat('MMM dd, yyyy h:mm a').format(dt);
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
