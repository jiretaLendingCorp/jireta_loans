// lib/presentation/features/head_manager/payments/screens/hm_payment_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import 'package:intl/intl.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

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
    final status = p['status'] as String? ?? '-';
    final method = p['payment_method'] as String? ?? '-';
    final refNum = p['reference_number'] as String? ?? '';
    final maskedRef = refNum.length > 4
        ? '${refNum.substring(0, 2)}****${refNum.substring(refNum.length - 2)}'
        : refNum;
    final statusColor = status == 'verified'
        ? AppColors.success
        : status == 'pending'
            ? AppColors.warning
            : AppColors.error;
    return ResponsiveRow(
      cells: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (maskedRef.isNotEmpty)
            Text(maskedRef,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: 1.0)),
          const SizedBox(height: 2),
          Text(
              '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'
                  .trim(),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ]),
        Text(loan['loan_number'] as String? ?? '-',
            style: const TextStyle(fontSize: 13)),
        Text('₱${fmt.format(p['amount'] ?? 0)}',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        _buildMethodBadge(method),
        Text(_formatDate(p['created_at']),
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        Container(
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
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4)),
      child: Text(label,
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
        context.showSnackBarAsToast(
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
    final dt = parseManila(d);
    if (dt == null) return d.toString();
    return DateFormat('MMM dd, yyyy h:mm a').format(dt);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
