// lib/presentation/features/employee/collections/screens/emp_collection_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../providers/emp_collection_provider.dart';
import '../widgets/emp_assign_rider_modal.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

// ── Payments state inside Employee Collections (mirrors HM) ──
class _EmpPaymentsState {
  final List<Map<String, dynamic>> payments;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  final String methodFilter;
  const _EmpPaymentsState({
    this.payments = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.methodFilter = 'all',
  });
  _EmpPaymentsState copyWith({
    List<Map<String, dynamic>>? payments,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    String? methodFilter,
  }) =>
      _EmpPaymentsState(
        payments: payments ?? this.payments,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        methodFilter: methodFilter ?? this.methodFilter,
      );
}

class _EmpPaymentsNotifier extends StateNotifier<_EmpPaymentsState>
    with RealtimeRefreshMixin {
  final PaymentRemoteDataSource _ds;
  _EmpPaymentsNotifier(this._ds) : super(const _EmpPaymentsState()) {
    bindRealtimeRefresh(['payments'], refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch({int page = 1, bool silent = false, String? method}) async {
    final m = method ?? state.methodFilter;
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getPaymentListPage(
        page: page,
        method: m == 'all' ? null : m,
      );
      final payments = (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      state = state.copyWith(
        payments: payments,
        isLoading: false,
        currentPage: meta['page'] as int? ?? 1,
        totalPages: meta['total_pages'] as int? ?? 1,
        methodFilter: m,
      );
    } catch (e) {
      if (silent) return;
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setMethod(String method) {
    state = state.copyWith(methodFilter: method);
    fetch(method: method);
  }

  Future<bool> reversePayment(String paymentId) async {
    try {
      await _ds.reversePayment(paymentId: paymentId, reason: 'Reversed by Employee');
      await fetch();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final _empPaymentsInCollectionProvider =
    StateNotifierProvider<_EmpPaymentsNotifier, _EmpPaymentsState>((ref) {
  return _EmpPaymentsNotifier(sl<PaymentRemoteDataSource>());
});

class EmpCollectionListScreen extends ConsumerStatefulWidget {
  const EmpCollectionListScreen({super.key});

  @override
  ConsumerState<EmpCollectionListScreen> createState() => _EmpCollectionListScreenState();
}

class _EmpCollectionListScreenState extends ConsumerState<EmpCollectionListScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _activeTab = 'all';

  final _dropdownTabs = const [
    _TabDef('all', 'All', Icons.layers_outlined),
    _TabDef('requested', 'Requested', Icons.hourglass_top_rounded),
    _TabDef('assigned', 'Assigned', Icons.assignment_ind_outlined),
    _TabDef('in_progress', 'In Progress', Icons.sync_rounded),
    _TabDef('completed', 'Completed', Icons.check_circle_rounded),
  ];

  final _pillTabs = const [
    _TabDef('payments', 'Payments', Icons.payments_outlined),
  ];

  final _paymentMethodTabs = const [
    _TabDef('all', 'All', Icons.layers_outlined),
    _TabDef('gcash', 'GCash', Icons.phone_android_rounded),
    _TabDef('office_cash', 'Office', Icons.storefront_rounded),
    _TabDef('rider_collection', 'Rider', Icons.delivery_dining_rounded),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onTabTap(String key) {
    if (key == _activeTab) return;
    setState(() => _activeTab = key);
    _searchCtrl.clear();
    if (key == 'payments') {
      ref.read(_empPaymentsInCollectionProvider.notifier).fetch(method: 'all');
    } else {
      ref.read(empCollectionProvider.notifier).setStatus(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collectionState = ref.watch(empCollectionProvider);
    final paymentsState = ref.watch(_empPaymentsInCollectionProvider);
    final isPayments = _activeTab == 'payments';

    return WebScaffold(
      title: 'Collections',
      body: Container(
        color: const Color(0xFFF0F2F5),
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTabPills(),
              const SizedBox(height: 16),
              _buildToolbar(collectionState, paymentsState, isPayments),
              const SizedBox(height: 16),
              if (isPayments) ...[
                _buildPaymentMethodFilter(paymentsState),
                const SizedBox(height: 12),
                if (paymentsState.isLoading)
                  _buildLoadingShimmer()
                else if (paymentsState.error != null && paymentsState.payments.isEmpty)
                  _buildPaymentError(paymentsState.error!)
                else if (_filteredPayments(paymentsState.payments).isEmpty)
                  _buildPaymentEmpty(paymentsState)
                else
                  _Entrance(child: _buildPaymentsTable(_filteredPayments(paymentsState.payments))),
                if (paymentsState.totalPages > 1) ...[
                  const SizedBox(height: 16),
                  _buildPaymentPagination(paymentsState),
                ],
              ] else ...[
                if (collectionState.isLoading)
                  _buildLoadingShimmer()
                else if (collectionState.error != null && collectionState.items.isEmpty)
                  _buildError(collectionState.error!)
                else
                  _buildCollectionsContent(collectionState),
                if (!collectionState.isLoading && collectionState.totalPages > 1) ...[
                  const SizedBox(height: 16),
                  _buildCollectionPagination(collectionState),
                ],
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabPills() {
    final dropdownKeys = _dropdownTabs.map((e) => e.key).toSet();
    final isDropdownActive = dropdownKeys.contains(_activeTab);
    final dropdownValue = isDropdownActive ? _activeTab : null;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDropdownActive ? AppColors.deepNavy : Colors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(
                color: isDropdownActive ? AppColors.deepNavy : AppColors.border,
                width: isDropdownActive ? 1.2 : 1,
              ),
              boxShadow: isDropdownActive
                  ? [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2))]
                  : null,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: dropdownValue,
                isDense: true,
                iconSize: 18,
                hint: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_list_rounded,
                        size: 12, color: isDropdownActive ? AppColors.gold : AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text('Collections',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDropdownActive ? Colors.white : AppColors.textSecondary)),
                  ],
                ),
                icon: Icon(Icons.arrow_drop_down_rounded, size: 16,
                    color: isDropdownActive ? Colors.white : AppColors.textTertiary),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDropdownActive ? Colors.white : AppColors.textSecondary,
                ),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                items: _dropdownTabs
                    .map((t) => DropdownMenuItem<String>(
                          value: t.key,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(t.icon, size: 12, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(t.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  _onTabTap(v);
                },
                selectedItemBuilder: (ctx) => _dropdownTabs
                    .map((t) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.icon, size: 12, color: AppColors.gold),
                            const SizedBox(width: 4),
                            Text(t.label,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                          ],
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ..._pillTabs.map((t) {
            final isActive = t.key == _activeTab;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _PillTab(def: t, active: isActive, onTap: () => _onTabTap(t.key)),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodFilter(_EmpPaymentsState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _paymentMethodTabs.map((t) {
          final isActive = t.key == state.methodFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => ref.read(_empPaymentsInCollectionProvider.notifier).setMethod(t.key),
              borderRadius: BorderRadius.zero,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.deepNavy : Colors.white,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: isActive ? AppColors.deepNavy : AppColors.border, width: isActive ? 1.2 : 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon, size: 12, color: isActive ? AppColors.gold : AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(t.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isActive ? Colors.white : AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildToolbar(EmpCollectionState cState, _EmpPaymentsState pState, bool isPayments) {
    final hasSearch = _searchCtrl.text.isNotEmpty;
    final resultsCount = isPayments
        ? _filteredPayments(pState.payments).length
        : _filteredCollections(cState.items).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: hasSearch ? AppColors.deepNavy : AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (hasSearch)
            InkWell(
              onTap: () {
                _searchCtrl.clear();
                setState(() {});
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppColors.textTertiary.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textSecondary),
              ),
            ),
          if (hasSearch) const SizedBox(width: 10),
          _ToolbarIcon(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: () => isPayments
                ? ref.read(_empPaymentsInCollectionProvider.notifier).fetch()
                : ref.read(empCollectionProvider.notifier).fetch(),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers_outlined, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text('$resultsCount results', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<dynamic> _filteredCollections(List<dynamic> items) {
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return items;
    return items.where((c) => c.loanNumber.toString().toLowerCase().contains(q) || c.lenderName.toString().toLowerCase().contains(q) || c.riderName.toString().toLowerCase().contains(q)).toList();
  }

  List<Map<String, dynamic>> _filteredPayments(List<Map<String, dynamic>> payments) {
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return payments;
    return payments.where((p) {
      final lender = p['lender'] as Map<String, dynamic>? ?? {};
      final loan = p['loan'] as Map<String, dynamic>? ?? {};
      final lenderName = '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.toLowerCase();
      final loanNum = (loan['loan_number'] ?? '').toString().toLowerCase();
      final method = (p['payment_method'] ?? '').toString().toLowerCase();
      return lenderName.contains(q) || loanNum.contains(q) || method.contains(q);
    }).toList();
  }

  Widget _buildCollectionsContent(EmpCollectionState state) {
    final items = _filteredCollections(state.items);
    if (items.isEmpty) {
      final isFiltered = _searchCtrl.text.isNotEmpty || state.statusFilter != 'all';
      if (isFiltered) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 16),
            Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.search_off_rounded, size: 36, color: AppColors.textTertiary)),
            const SizedBox(height: 14),
            const Text('No matches', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Try a different search or status filter', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: () { _searchCtrl.clear(); ref.read(empCollectionProvider.notifier).setStatus('all'); setState(() {}); }, icon: const Icon(Icons.clear_all_rounded, size: 16), label: const Text('Clear filters')),
          ]),
        );
      }
      return _buildEmpty();
    }
    return _Entrance(
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 14, offset: Offset(0, 4))]),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(color: Color(0xFFF8F9FB), border: Border(bottom: BorderSide(color: AppColors.border))),
                  child: const Row(
                    children: [
                      Expanded(flex: 3, child: _HLabel('Lender & Loan', Icons.person_outline)),
                      Expanded(flex: 2, child: _HLabel('Amount', Icons.payments_outlined)),
                      Expanded(flex: 2, child: _HLabel('Rider', Icons.delivery_dining_outlined)),
                      Expanded(flex: 2, child: _HLabel('Status', Icons.flag_outlined)),
                      SizedBox(width: 96, child: _HLabel('Action', Icons.bolt_outlined)),
                    ],
                  ),
                ),
                ...items.asMap().entries.map((e) => _buildCollectionRow(e.value, e.key.isEven)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionRow(dynamic col, bool isEven) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final schedule = col.loanSchedule as Map<String, dynamic>? ?? {};
    final isOffice = col.collectionType == 'office';
    final amount = col.amountCollected ?? (schedule['amount_due'] as num?)?.toDouble() ?? 0.0;
    final status = (col.status?.toString() ?? '').toLowerCase();
    final accent = _accentForStatus(status);
    final canAssign = col.status == 'requested' && !isOffice;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: isEven ? Colors.white : const Color(0xFFFDFDFD), border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(col.loanNumber.isNotEmpty ? col.loanNumber : '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(col.lenderName.isNotEmpty ? col.lenderName : 'Unknown lender', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary), overflow: TextOverflow.ellipsis),
            ]),
          ),
          Expanded(flex: 2, child: Text('₱${fmt.format(amount)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: amount > 0 ? AppColors.deepNavy : AppColors.textSecondary))),
          Expanded(flex: 2, child: Row(children: [Icon(isOffice ? Icons.storefront_rounded : Icons.delivery_dining_rounded, size: 14, color: AppColors.textTertiary), const SizedBox(width: 6), Flexible(child: Text(isOffice ? 'Office' : (col.riderName.isNotEmpty ? col.riderName : '—'), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis))])),
          Expanded(
            flex: 2,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(child: Text(status.split('_').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '').join(' '), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent), overflow: TextOverflow.ellipsis)),
            ]),
          ),
          SizedBox(
            width: 96,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (canAssign)
                InkWell(
                  onTap: () async {
                    final loanScheduleId = col.loanScheduleId as String? ?? '';
                    final loanId = (col.loanSchedule?['loan']?['id'] as String?) ?? (col.loanSchedule?['loan_id'] as String?) ?? '';
                    final result = await showDialog<bool>(context: context, builder: (_) => EmpAssignRiderModal(loanScheduleId: loanScheduleId, loanId: loanId, assignmentId: col.id as String? ?? ''));
                    if (result == true && mounted) context.showSnackBarAsToast(const SnackBar(content: Text('Rider assigned successfully'), backgroundColor: AppColors.success));
                  },
                  borderRadius: BorderRadius.circular(9),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: AppColors.riderGreen, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.delivery_dining_rounded, size: 14, color: Colors.white)),
                ),
              if (canAssign) const SizedBox(width: 6),
              InkWell(
                onTap: () => context.go(RouteConstants.empCollectionDetails.replaceFirst(':id', col.id)),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.visibility_outlined, size: 14, color: AppColors.deepNavy), SizedBox(width: 4), Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.deepNavy))])),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsTable(List<Map<String, dynamic>> payments) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final dateFmt = DateFormat('MMM dd, yyyy');
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 14, offset: Offset(0, 4))]),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(color: Color(0xFFF8F9FB), border: Border(bottom: BorderSide(color: AppColors.border))),
            child: const Row(
              children: [
                Expanded(flex: 3, child: _HLabel('Lender & Loan', Icons.person_outline)),
                Expanded(flex: 2, child: _HLabel('Amount', Icons.payments_outlined)),
                Expanded(flex: 2, child: _HLabel('Method', Icons.account_balance_wallet_outlined)),
                Expanded(flex: 2, child: _HLabel('Date', Icons.event_outlined)),
                Expanded(flex: 2, child: _HLabel('Status', Icons.flag_outlined)),
                SizedBox(width: 96, child: _HLabel('Action', Icons.bolt_outlined)),
              ],
            ),
          ),
          ...payments.asMap().entries.map((e) {
            final p = e.value;
            final isEven = e.key.isEven;
            final lender = p['lender'] as Map<String, dynamic>? ?? {};
            final loan = p['loan'] as Map<String, dynamic>? ?? {};
            final status = (p['status'] as String? ?? '-').toLowerCase();
            final method = (p['payment_method'] as String? ?? p['method'] as String? ?? '-').toLowerCase();
            final amt = (p['amount'] as num?)?.toDouble() ?? 0;
            final statusColor = status == 'verified' ? AppColors.success : status == 'pending' ? AppColors.warning : AppColors.error;
            final dateStr = () {
              final d = p['created_at'];
              if (d == null) return '-';
              try { return dateFmt.format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
            }();
            final flatLenderName = p['lender_name'] != null ? p['lender_name'] as String : null;
            final resolvedLender = flatLenderName != null && flatLenderName.isNotEmpty
                ? flatLenderName
                : ('${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim().isEmpty ? '—' : '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim());
            final loanNumberFlat = p['loan_number'] as String? ?? loan['loan_number'] as String? ?? '—';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: isEven ? Colors.white : const Color(0xFFFDFDFD), border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(resolvedLender, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.deepNavy.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)), child: Text(loanNumberFlat, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.deepNavy))),
                    ]),
                  ),
                  Expanded(flex: 2, child: Text('₱${fmt.format(amt)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
                  Expanded(flex: 2, child: _PaymentMethodInline(method: method)),
                  Expanded(flex: 2, child: Text(dateStr, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                  Expanded(
                    flex: 2,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(status.split('_').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '').join(' '), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor), overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                  SizedBox(
                    width: 96,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: status == 'verified'
                          ? InkWell(
                              onTap: () => _confirmReverse(p['id'] as String? ?? ''),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.error.withValues(alpha: 0.5))), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.undo_rounded, size: 14, color: AppColors.error), SizedBox(width: 4), Text('Reverse', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.error))])),
                            )
                          : InkWell(
                              onTap: () {
                                final id = p['id'] as String? ?? '';
                                if (id.isNotEmpty) context.go(RouteConstants.empPaymentDetails.replaceFirst(':id', id));
                              },
                              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.visibility_outlined, size: 14, color: AppColors.deepNavy), SizedBox(width: 4), Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.deepNavy))])),
                            ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _confirmReverse(String paymentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reverse Payment'),
        content: const Text('Are you sure you want to reverse this payment? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.error), child: const Text('Reverse')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final ok = await ref.read(_empPaymentsInCollectionProvider.notifier).reversePayment(paymentId);
      if (mounted) context.showSnackBarAsToast(SnackBar(content: Text(ok ? 'Payment reversed' : 'Failed to reverse payment'), backgroundColor: ok ? AppColors.success : AppColors.error));
    }
  }

  Color _accentForStatus(String s) {
    switch (s) {
      case 'requested':
        return AppColors.warning;
      case 'assigned':
        return AppColors.lenderBlue;
      case 'accepted':
        return AppColors.riderGreen;
      case 'in_progress':
        return const Color(0xFFFFA000);
      case 'completed':
        return AppColors.riderGreen;
      case 'failed':
      case 'declined':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildLoadingShimmer() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(6, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.shimmerBase.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 12, decoration: BoxDecoration(color: AppColors.shimmerBase.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 8),
              Container(height: 10, width: 160, decoration: BoxDecoration(color: AppColors.shimmerHighlight.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6))),
            ])),
            const SizedBox(width: 16),
            Container(width: 86, height: 28, decoration: BoxDecoration(color: AppColors.shimmerBase.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(20))),
          ]),
        )),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.cloud_off_rounded, size: 32, color: AppColors.error)),
          const SizedBox(height: 14),
          const Text('Failed to load collections', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: () => ref.read(empCollectionProvider.notifier).fetch(), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Retry'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.deepNavy, foregroundColor: Colors.white)),
        ]),
      ),
    );
  }

  Widget _buildPaymentError(String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.cloud_off_rounded, size: 32, color: AppColors.error)),
          const SizedBox(height: 14),
          const Text('Failed to load payments', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: () => ref.read(_empPaymentsInCollectionProvider.notifier).fetch(), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Retry'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.deepNavy, foregroundColor: Colors.white)),
        ]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))]),
      child: Column(children: [
        Container(width: 72, height: 72, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.riderGreen.withValues(alpha: 0.12), AppColors.deepNavy.withValues(alpha: 0.08)]), borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)), child: const Icon(Icons.delivery_dining_rounded, size: 40, color: AppColors.riderGreen)),
        const SizedBox(height: 16),
        const Text('No collections found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Rider collection assignments will appear here once requested.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildPaymentEmpty(_EmpPaymentsState state) {
    final isFiltered = _searchCtrl.text.isNotEmpty || state.methodFilter != 'all';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))]),
      child: Column(children: [
        Container(width: 72, height: 72, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.deepNavy.withValues(alpha: 0.10), AppColors.gold.withValues(alpha: 0.16)]), shape: BoxShape.circle, border: Border.all(color: AppColors.border)), child: Icon(isFiltered ? Icons.search_off_rounded : Icons.payments_outlined, size: 32, color: AppColors.deepNavy.withValues(alpha: 0.75))),
        const SizedBox(height: 16),
        Text(isFiltered ? 'No matching payments' : 'No payments found', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(isFiltered ? 'Try a different search or method filter.' : 'Verified payments will appear here.', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
        if (isFiltered) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(onPressed: () { _searchCtrl.clear(); ref.read(_empPaymentsInCollectionProvider.notifier).setMethod('all'); setState(() {}); }, icon: const Icon(Icons.clear_all_rounded, size: 16), label: const Text('Clear filters')),
        ],
      ]),
    );
  }

  Widget _buildCollectionPagination(EmpCollectionState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Text('Page ${state.currentPage} of ${state.totalPages}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const Spacer(),
        _PageBtn(icon: Icons.chevron_left_rounded, enabled: state.currentPage > 1, onTap: () => ref.read(empCollectionProvider.notifier).fetch(page: state.currentPage - 1)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(20)), child: Text('${state.currentPage} / ${state.totalPages}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
        const SizedBox(width: 8),
        _PageBtn(icon: Icons.chevron_right_rounded, enabled: state.currentPage < state.totalPages, onTap: () => ref.read(empCollectionProvider.notifier).fetch(page: state.currentPage + 1)),
      ]),
    );
  }

  Widget _buildPaymentPagination(_EmpPaymentsState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Text('Page ${state.currentPage} of ${state.totalPages}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const Spacer(),
        _PageBtn(icon: Icons.chevron_left_rounded, enabled: state.currentPage > 1, onTap: () => ref.read(_empPaymentsInCollectionProvider.notifier).fetch(page: state.currentPage - 1)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(20)), child: Text('${state.currentPage} / ${state.totalPages}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
        const SizedBox(width: 8),
        _PageBtn(icon: Icons.chevron_right_rounded, enabled: state.currentPage < state.totalPages, onTap: () => ref.read(_empPaymentsInCollectionProvider.notifier).fetch(page: state.currentPage + 1)),
      ]),
    );
  }
}

class _TabDef {
  final String key;
  final String label;
  final IconData icon;
  const _TabDef(this.key, this.label, this.icon);
}

class _PillTab extends StatelessWidget {
  final _TabDef def;
  final bool active;
  final VoidCallback onTap;
  const _PillTab({required this.def, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.deepNavy : Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: active ? AppColors.deepNavy : AppColors.border, width: active ? 1.2 : 1),
          boxShadow: active ? [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(def.icon, size: 12, color: active ? AppColors.gold : AppColors.textTertiary),
          const SizedBox(width: 4),
          Text(def.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _HLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  const _HLabel(this.text, this.icon);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: AppColors.textTertiary),
      const SizedBox(width: 6),
      Flexible(child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5), overflow: TextOverflow.ellipsis)),
    ]);
  }
}

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
        label = method.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
        icon = Icons.payments_outlined;
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: c),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
    ]);
  }
}

class _ToolbarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ToolbarIcon({required this.icon, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9), border: Border.all(color: AppColors.border)), child: Icon(icon, size: 16, color: AppColors.textSecondary)),
      ),
    );
  }
}

class _PageBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PageBtn({required this.icon, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(width: 36, height: 36, decoration: BoxDecoration(color: enabled ? Colors.white : AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8), border: Border.all(color: enabled ? AppColors.border : AppColors.divider)), child: Icon(icon, size: 18, color: enabled ? AppColors.textPrimary : AppColors.textTertiary)),
    );
  }
}

class _Entrance extends StatefulWidget {
  final Widget child;
  const _Entrance({required this.child});
  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _offset = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: SlideTransition(position: _offset, child: widget.child));
  }
}
