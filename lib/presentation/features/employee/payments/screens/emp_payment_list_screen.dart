// lib/presentation/features/employee/payments/screens/emp_payment_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
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
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            ...state.payments.asMap().entries.map((e) => _buildRow(e.value, e.key.isEven, fmt)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const s = TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surfaceVariant,
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('LENDER', style: s)),
          Expanded(flex: 2, child: Text('LOAN #', style: s)),
          Expanded(flex: 2, child: Text('AMOUNT', style: s)),
          Expanded(flex: 2, child: Text('METHOD', style: s)),
          Expanded(flex: 2, child: Text('DATE', style: s)),
          Expanded(flex: 2, child: Text('STATUS', style: s)),
          Expanded(flex: 1, child: Text('', style: s)),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> p, bool isEven, NumberFormat fmt) {
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
    return InkWell(
      onTap: () {
        final id = p['id'] as String? ?? '';
        if (id.isNotEmpty) context.go(RouteConstants.empPaymentDetails.replaceFirst(':id', id));
      },
      child: Container(
        key: ValueKey(p['id']),
        color: isEven ? Colors.white : AppColors.surfaceVariant.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
                flex: 3,
                child: Text(resolvedLender.isEmpty ? '-' : resolvedLender,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            Expanded(
                flex: 2,
                child: Text(displayLoan.isEmpty ? '-' : displayLoan, style: const TextStyle(fontSize: 13))),
            Expanded(
                flex: 2,
                child: Text('₱${fmt.format(p['amount'] ?? 0)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            Expanded(flex: 2, child: _buildMethodBadge(method)),
            Expanded(
                flex: 2,
                child: Text(_formatDate(p['created_at']),
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration:
                    BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                child: Text(_capitalize(status),
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500)),
              ),
            ),
            Expanded(
              flex: 1,
              child: status == 'verified'
                  ? Tooltip(
                      message: 'Reverse Payment',
                      child: IconButton(
                        onPressed: () => _confirmReverse(p['id'] as String? ?? ''),
                        icon: const Icon(Icons.undo, size: 18, color: AppColors.error),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
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
    try {
      return DateFormat('MMM dd, yyyy').format(DateTime.parse(d.toString()));
    } catch (_) {
      return d.toString();
    }
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
