// lib/presentation/features/head_manager/payments/screens/hm_payment_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import 'package:intl/intl.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class _PaymentState {
  final List<Map<String, dynamic>> payments;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  const _PaymentState(
      {this.payments = const [],
      this.isLoading = false,
      this.error,
      this.currentPage = 1,
      this.totalPages = 1});
  _PaymentState copyWith(
          {List<Map<String, dynamic>>? payments,
          bool? isLoading,
          String? error,
          int? currentPage,
          int? totalPages}) =>
      _PaymentState(
          payments: payments ?? this.payments,
          isLoading: isLoading ?? this.isLoading,
          error: error,
          currentPage: currentPage ?? this.currentPage,
          totalPages: totalPages ?? this.totalPages);
}

class _PaymentNotifier extends StateNotifier<_PaymentState>
    with RealtimeRefreshMixin<_PaymentState> {
  final PaymentRemoteDataSource _ds;
  _PaymentNotifier(this._ds) : super(const _PaymentState()) {
    bindRealtimeRefresh(['payments'], refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch(
      {int page = 1, String? method, String? status, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getPaymentListPage(
          page: page, method: method, status: status);
      final payments =
          (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
          payments: payments,
          isLoading: false,
          currentPage: meta['page'] as int? ?? 1,
          totalPages: meta['total_pages'] as int? ?? 1);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<bool> reversePayment(String paymentId) async {
    try {
      await _ds.reversePayment(
          paymentId: paymentId, reason: 'Reversed by Head Manager');
      await fetch();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final _hmPaymentProvider =
    AutoDisposeStateNotifierProvider<_PaymentNotifier, _PaymentState>((ref) {
  return _PaymentNotifier(sl<PaymentRemoteDataSource>());
});

class HmPaymentListScreen extends ConsumerStatefulWidget {
  const HmPaymentListScreen({super.key});

  @override
  ConsumerState<HmPaymentListScreen> createState() =>
      _HmPaymentListScreenState();
}

class _HmPaymentListScreenState extends ConsumerState<HmPaymentListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _tabs = [
    ('all', 'All'),
    ('gcash', 'GCash'),
    ('cash', 'Cash'),
    ('rider_collection', 'Collections')
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
    ref
        .read(_hmPaymentProvider.notifier)
        .fetch(method: tab == 'all' ? null : tab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_hmPaymentProvider);
    return WebScaffold(
      title: 'Payments',
      actions: [
        IconButton(
            onPressed: () => ref.read(_hmPaymentProvider.notifier).fetch(),
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

  Widget _buildTable(_PaymentState state) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border)),
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            ...state.payments
                .asMap()
                .entries
                .map((e) => _buildRow(e.value, e.key.isEven, fmt)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const s = TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: AppColors.textSecondary);
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
    final status = p['status'] as String? ?? '-';
    final method = p['payment_method'] as String? ?? '-';
    final statusColor = status == 'verified'
        ? AppColors.success
        : status == 'pending'
            ? AppColors.warning
            : AppColors.error;
    return Container(
      key: ValueKey(p['id']),
      color: isEven
          ? Colors.white
          : AppColors.surfaceVariant.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Text(
                  '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'
                      .trim(),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500))),
          Expanded(
              flex: 2,
              child: Text(loan['loan_number'] as String? ?? '-',
                  style: const TextStyle(fontSize: 13))),
          Expanded(
              flex: 2,
              child: Text('₱${fmt.format(p['amount'] ?? 0)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: _buildMethodBadge(method)),
          Expanded(
              flex: 2,
              child: Text(_formatDate(p['created_at']),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary))),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(_capitalize(status),
                  style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          Expanded(
            flex: 1,
            child: status == 'verified'
                ? Tooltip(
                    message: 'Reverse Payment',
                    child: IconButton(
                      onPressed: () =>
                          _confirmReverse(p['id'] as String? ?? ''),
                      icon: const Icon(Icons.undo,
                          size: 18, color: AppColors.error),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodBadge(String method) {
    Color c;
    switch (method) {
      case 'gcash':
        c = AppColors.lenderBlue;
        break;
      case 'cash':
        c = AppColors.riderGreen;
        break;
      default:
        c = AppColors.info;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4)),
      child: Text(_capitalize(method.replaceAll('_', ' ')),
          style:
              TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildEmpty() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined,
                size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text('No payments found',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          ],
        ),
      );

  Future<void> _confirmReverse(String paymentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reverse Payment'),
        content: const Text(
            'Are you sure you want to reverse this payment? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Reverse')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final ok =
          await ref.read(_hmPaymentProvider.notifier).reversePayment(paymentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(ok ? 'Payment reversed' : 'Failed to reverse payment'),
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

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
