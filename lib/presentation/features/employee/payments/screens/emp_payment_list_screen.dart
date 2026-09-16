// lib/presentation/features/employee/payments/screens/emp_payment_list_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../shared/widgets/filter_pill_tab.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/pending_payments_table.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../collections/providers/emp_collection_provider.dart';
import '../providers/emp_payment_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class EmpPaymentListScreen extends ConsumerStatefulWidget {
  const EmpPaymentListScreen({super.key});

  @override
  ConsumerState<EmpPaymentListScreen> createState() =>
      _EmpPaymentListScreenState();
}

class _EmpPaymentListScreenState extends ConsumerState<EmpPaymentListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  DateTimeRange? _dateRange;

  /// True kapag "All Pending Payment" ang naka-select — galing sa collections
  /// ang table (hindi pa bayad/na-kolekta), hindi sa payments list.
  bool _pendingPayments = false;

  static const _paymentMethodTabs = [
    FilterTabDef('all', 'All', Icons.layers_outlined),
    // Lahat ng HINDI pa bayad/na-kolekta na installment — dito pwedeng
    // i-mark na "Paid in Office" ang mga office request.
    FilterTabDef('pending_payments', 'All Pending Payment',
        Icons.pending_actions_rounded),
    FilterTabDef('office_cash', 'Office', Icons.storefront_rounded),
    FilterTabDef('rider_collection', 'Cash on Delivery',
        Icons.delivery_dining_rounded),
    FilterTabDef('gcash', 'GCash', Icons.phone_android_rounded),
  ];

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onMethodTap(String key) {
    final term = _searchCtrl.text.trim();
    if (key == 'pending_payments') {
      setState(() => _pendingPayments = true);
      final notifier = ref.read(empCollectionProvider.notifier);
      // Isang fetch lang (status + search) — at kasama ang date filter.
      notifier.setFilters(status: 'pending', search: term);
      if (_dateRange != null) _applyDateRangeToCollections();
      return;
    }
    setState(() => _pendingPayments = false);
    // Method + search sa isang fetch; nasa provider na ang active na uri ng
    // payment kaya hindi na kailangan ng lokal na `_methodFilter`.
    ref.read(empPaymentListProvider.notifier).setFilters(method: key, search: term);
  }

  /// Search box — naka-debounce para hindi bawat letra ay may request.
  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      final term = v.trim();
      if (_pendingPayments) {
        ref.read(empCollectionProvider.notifier).setFilters(search: term);
      } else {
        ref.read(empPaymentListProvider.notifier).setFilters(search: term);
      }
    });
  }

  void _applyDateRangeToCollections() {
    final r = _dateRange;
    ref.read(empCollectionProvider.notifier).setDateRange(
          r == null ? null : SearchDateFilter.fromParam(r.start),
          r == null ? null : SearchDateFilter.toParam(r.end),
        );
  }

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    ref.read(empPaymentListProvider.notifier).setDateRange(
          r == null ? null : SearchDateFilter.fromParam(r.start),
          r == null ? null : SearchDateFilter.toParam(r.end),
        );
    // Ang collections provider ay buhay lang habang naka-select ang
    // "All Pending Payment" — doon lang i-apply.
    if (_pendingPayments) _applyDateRangeToCollections();
  }

  void _refresh() {
    if (_pendingPayments) {
      ref.read(empCollectionProvider.notifier).fetch();
      return;
    }
    ref.read(empPaymentListProvider.notifier).fetch();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empPaymentListProvider);
    // Ang collections provider ay kailangan lang ng "All Pending Payment" tab
    // — kaya hindi ito binubuksan (at hindi nag-fefetch) sa ibang pill.
    final collectionState =
        _pendingPayments ? ref.watch(empCollectionProvider) : null;

    return WebScaffold(
      title: 'Payments',
      actions: [
        IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh'),
        const SizedBox(width: 12),
      ],
      body: Container(
        color: const Color(0xFFF0F2F5),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPaymentMethodFilter(state),
              const SizedBox(height: 16),
              _buildToolbar(state, collectionState),
              const SizedBox(height: 16),
              if (collectionState != null)
                ..._buildPendingSection(collectionState)
              else
                ..._buildPaymentsSection(state),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Search + Filter Date + "N results" — gaya ng toolbar sa Collections.
  Widget _buildToolbar(
      EmpPaymentState state, EmpCollectionState? collectionState) {
    final count = _pendingPayments
        ? (collectionState?.totalCount ?? 0)
        : state.totalCount;
    return ResponsiveSearchToolbar(
      searchField: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search payments...',
          prefixIcon: const Icon(Icons.search, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: _onSearchChanged,
      ),
      trailing: [
        SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
        SearchResultsChip(count: count),
      ],
    );
  }

  // ── Uri ng payment: pill tabs (All · GCash · Office · COD · Pending) ──
  Widget _buildPaymentMethodFilter(EmpPaymentState state) {
    final active = _pendingPayments ? 'pending_payments' : state.methodFilter;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _paymentMethodTabs.map((t) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterPillTab(
              def: t,
              active: t.key == active,
              onTap: () => _onMethodTap(t.key),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildPaymentsSection(EmpPaymentState state) {
    final children = <Widget>[];
    if (state.isLoading && state.payments.isEmpty) {
      children.add(const ShimmerLoader());
    } else if (state.error != null && state.payments.isEmpty) {
      children.add(_buildError(
        state.error!,
        onRetry: () => ref.read(empPaymentListProvider.notifier).fetch(),
      ));
    } else if (state.payments.isEmpty) {
      children.add(_buildEmpty('No payments found'));
    } else {
      children.add(_buildTable(state));
    }
    if (state.totalPages > 1) {
      children.add(const SizedBox(height: 16));
      children.add(_buildPagination(
        currentPage: state.currentPage,
        totalPages: state.totalPages,
        onPage: (p) => ref.read(empPaymentListProvider.notifier).fetch(page: p),
      ));
    }
    return children;
  }

  List<Widget> _buildPendingSection(EmpCollectionState state) {
    final children = <Widget>[];
    if (state.isLoading && state.items.isEmpty) {
      children.add(const ShimmerLoader());
    } else if (state.error != null && state.items.isEmpty) {
      children.add(_buildError(
        state.error!,
        onRetry: () => ref.read(empCollectionProvider.notifier).fetch(),
      ));
    } else if (state.items.isEmpty) {
      children.add(_buildEmpty('No pending payments'));
    } else {
      children.add(PendingPaymentsTable(
        items: state.items,
        onView: (c) => context.go(
            RouteConstants.empCollectionDetails.replaceFirst(':id', c.id)),
        onRefresh: () async {
          await ref.read(empCollectionProvider.notifier).fetch(silent: true);
          await ref.read(empPaymentListProvider.notifier).fetch(silent: true);
        },
      ));
    }
    if (state.totalPages > 1) {
      children.add(const SizedBox(height: 16));
      children.add(_buildPagination(
        currentPage: state.currentPage,
        totalPages: state.totalPages,
        onPage: (p) => ref.read(empCollectionProvider.notifier).fetch(page: p),
      ));
    }
    return children;
  }

  Widget _buildTable(EmpPaymentState state) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final dateFmt = DateFormat('MMM dd, yyyy h:mm a');
    return ResponsiveListCard(
      minTableWidth: 900,
      columns: const [
        ResponsiveCol('Lender & Loan', icon: Icons.person_outline, flex: 3),
        ResponsiveCol('Amount', icon: Icons.payments_outlined, flex: 2),
        ResponsiveCol('Method',
            icon: Icons.account_balance_wallet_outlined, flex: 2),
        ResponsiveCol('Date', icon: Icons.event_outlined, flex: 2),
        ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 2),
      ],
      actionsCol: const ResponsiveActionsCol(width: 96),
      rows: state.payments.map((p) => _buildRow(p, fmt, dateFmt)).toList(),
    );
  }

  ResponsiveRow _buildRow(
      Map<String, dynamic> p, NumberFormat fmt, DateFormat dateFmt) {
    final lender = p['lender'] as Map<String, dynamic>? ?? {};
    final loan = p['loan'] as Map<String, dynamic>? ?? {};
    // Flat fields kapag hindi nested ang lender/loan sa response.
    final flatLenderName = p['lender_name'] as String?;
    final resolvedLender = (flatLenderName != null && flatLenderName.isNotEmpty)
        ? flatLenderName
        : '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim();
    final displayLoan = (p['loan_number'] as String?) ??
        (p['loan']?['loan_number'] as String?) ??
        loan['loan_number'] as String? ??
        '-';
    final status = (p['status'] as String? ?? '-').toLowerCase();
    final method = (p['payment_method'] as String? ??
            p['method'] as String? ??
            '-')
        .toLowerCase();
    final amt = (p['amount'] as num?)?.toDouble() ?? 0;
    final statusColor = status == 'verified'
        ? AppColors.success
        : status == 'pending'
            ? AppColors.warning
            : AppColors.error;
    return ResponsiveRow(
      cells: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(resolvedLender.isEmpty ? '—' : resolvedLender,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(displayLoan.isEmpty ? '—' : displayLoan,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
        ]),
        Text('₱${fmt.format(amt)}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        _PaymentMethodInline(method: method),
        Text(_formatDate(p['created_at'], dateFmt),
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status
                  .split('_')
                  .map((w) =>
                      w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
                  .join(' '),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ],
      actions: status == 'verified'
          ? _ActionPill(
              label: 'Reverse',
              icon: Icons.undo_rounded,
              color: AppColors.error,
              outlined: true,
              onTap: () => _confirmReverse(p['id'] as String? ?? ''),
            )
          : _ActionPill(
              label: 'View',
              icon: Icons.visibility_outlined,
              color: AppColors.deepNavy,
              onTap: () {
                final id = p['id'] as String? ?? '';
                if (id.isNotEmpty) {
                  context.go(
                      RouteConstants.empPaymentDetails.replaceFirst(':id', id));
                }
              },
            ),
    );
  }

  Widget _buildError(String message, {required VoidCallback onRetry}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: Column(children: [
        const Icon(Icons.cloud_off_rounded, size: 32, color: AppColors.error),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepNavy,
              foregroundColor: Colors.white),
        ),
      ]),
    );
  }

  Widget _buildEmpty(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.payments_outlined,
                  size: 64, color: AppColors.textTertiary),
              const SizedBox(height: 16),
              Text(message,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 16)),
            ],
          ),
        ),
      );

  Widget _buildPagination({
    required int currentPage,
    required int totalPages,
    required ValueChanged<int> onPage,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(children: [
        const Spacer(),
        _PageBtn(
            icon: Icons.chevron_left_rounded,
            enabled: currentPage > 1,
            onTap: () => onPage(currentPage - 1)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(20)),
          child: Text('$currentPage / $totalPages',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
        const SizedBox(width: 8),
        _PageBtn(
            icon: Icons.chevron_right_rounded,
            enabled: currentPage < totalPages,
            onTap: () => onPage(currentPage + 1)),
      ]),
    );
  }

  Future<void> _confirmReverse(String paymentId) async {
    if (paymentId.isEmpty) return;
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
      final ok = await ref
          .read(empPaymentListProvider.notifier)
          .reversePayment(paymentId);
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

  String _formatDate(dynamic d, DateFormat fmt) {
    if (d == null) return '-';
    final dt = parseManila(d);
    if (dt == null) return d.toString();
    return fmt.format(dt);
  }
}

/// Icon + label na uri ng payment sa table (gaya ng Collections).
class _PaymentMethodInline extends StatelessWidget {
  final String method;
  const _PaymentMethodInline({required this.method});

  @override
  Widget build(BuildContext context) {
    Color c;
    String label;
    IconData icon;
    switch (method) {
      case 'gcash':
      case 'gcash_xendit':
        c = AppColors.lenderBlue;
        label = 'GCash';
        icon = Icons.phone_android_rounded;
        break;
      case 'office_cash':
      case 'cash':
        c = AppColors.success;
        label = 'Office';
        icon = Icons.storefront_rounded;
        break;
      case 'rider_collection':
        c = AppColors.riderGreen;
        label = 'Rider';
        icon = Icons.delivery_dining_rounded;
        break;
      default:
        c = AppColors.textSecondary;
        label = method
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) =>
                w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
        icon = Icons.payments_outlined;
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: c),
      const SizedBox(width: 6),
      Flexible(
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: c),
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

/// View / Reverse button sa actions column (gaya ng Collections).
class _ActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool outlined;
  final VoidCallback onTap;
  const _ActionPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color:
                    outlined ? color.withValues(alpha: 0.5) : AppColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}

class _PageBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PageBtn(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: enabled ? Colors.white : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: enabled ? AppColors.border : AppColors.divider)),
        child: Icon(icon,
            size: 18,
            color: enabled ? AppColors.textPrimary : AppColors.textTertiary),
      ),
    );
  }
}
