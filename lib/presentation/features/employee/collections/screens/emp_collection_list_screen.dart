// lib/presentation/features/employee/collections/screens/emp_collection_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';
import '../../../../shared/widgets/details/user_details_modal.dart';
import '../../../../shared/widgets/early_payer_badge.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/pending_payments_table.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/filter_pill_tab.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../lenders/providers/emp_lender_provider.dart';
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
  final int totalCount;
  final String methodFilter;
  final String search;
  const _EmpPaymentsState({
    this.payments = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.methodFilter = 'all',
    this.search = '',
  });
  _EmpPaymentsState copyWith({
    List<Map<String, dynamic>>? payments,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    String? methodFilter,
    String? search,
  }) =>
      _EmpPaymentsState(
        payments: payments ?? this.payments,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        totalCount: totalCount ?? this.totalCount,
        methodFilter: methodFilter ?? this.methodFilter,
        search: search ?? this.search,
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
        search: state.search.isEmpty ? null : state.search,
      );
      final payments = (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      state = state.copyWith(
        payments: payments,
        isLoading: false,
        currentPage: meta['page'] as int? ?? 1,
        totalPages: meta['total_pages'] as int? ?? 1,
        totalCount: (meta['total'] as num?)?.toInt() ?? payments.length,
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

  void setSearch(String s) {
    state = state.copyWith(search: s);
    fetch();
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
  /// Assignment na kasalukuyang ini-approve/re-reject — para makita ang
  /// spinner sa mismong button habang tumatakbo ang request.
  String? _reviewingId;
  final _scrollCtrl = ScrollController();
  DateTimeRange? _dateRange;
  String _activeTab = 'all';

  final _dropdownTabs = const [
    FilterTabDef('all', 'All', Icons.layers_outlined),
    FilterTabDef('requested', 'Requested', Icons.hourglass_top_rounded),
    FilterTabDef('assigned', 'Assigned', Icons.assignment_ind_outlined),
    FilterTabDef('in_progress', 'In Progress', Icons.sync_rounded),
    // Rider submitted — kailangan ng approval bago bumaba ang loan balance.
    FilterTabDef('pending_approval', 'Pending Approval', Icons.hourglass_top_rounded),
    FilterTabDef('completed', 'Completed', Icons.check_circle_rounded),
    FilterTabDef('rejected', 'Rejected', Icons.cancel_outlined),
  ];

  final _pillTabs = const [
    FilterTabDef('payments', 'Payments', Icons.payments_outlined),
    // Early payers ay lender attribute — dating badge sa People/Lenders list.
    // Nasa Collections na sila ngayon kasama ng Payments.
    FilterTabDef('early_payers', 'Early Payers', Icons.bolt_rounded),
  ];

  final _paymentMethodTabs = const [
    FilterTabDef('all', 'All', Icons.layers_outlined),
    // Lahat ng HINDI pa bayad/na-kolekta na installment (kasama ang office) —
    // dito pwedeng i-mark na "Paid in Office" ang mga office request.
    FilterTabDef('pending_payments', 'All Pending Payment',
        Icons.pending_actions_rounded),
    FilterTabDef('office_cash', 'Office', Icons.storefront_rounded),
    FilterTabDef('rider_collection', 'Cash on Delivery', Icons.delivery_dining_rounded),
    FilterTabDef('gcash', 'GCash', Icons.phone_android_rounded),
  ];

  /// True kapag "All Pending Payment" ang naka-select sa payment pills.
  bool _pendingPayments = false;

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    ref.read(empCollectionProvider.notifier).setDateRange(
          r == null ? null : SearchDateFilter.fromParam(r.start),
          r == null ? null : SearchDateFilter.toParam(r.end),
        );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onTabTap(String key) {
    if (key == _activeTab) return;
    setState(() {
      _activeTab = key;
      _pendingPayments = false;
    });
    _searchCtrl.clear();
    ref.read(empCollectionProvider.notifier).setSearch('');
    ref.read(_empPaymentsInCollectionProvider.notifier).setSearch('');
    if (key == 'payments') {
      ref.read(_empPaymentsInCollectionProvider.notifier).fetch(method: 'all');
    } else if (key == 'early_payers') {
      // Lender list na may `is_early_payer` insight — client-side na search.
      ref.read(empLenderProvider.notifier).load(silent: true);
    } else {
      ref.read(empCollectionProvider.notifier).setStatus(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collectionState = ref.watch(empCollectionProvider);
    final paymentsState = ref.watch(_empPaymentsInCollectionProvider);
    final lenderState = ref.watch(empLenderProvider);
    final isPayments = _activeTab == 'payments';
    final isEarlyPayers = _activeTab == 'early_payers';

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
                if (_pendingPayments) ...[
                  if (collectionState.isLoading)
                    _buildLoadingShimmer()
                  else if (collectionState.error != null &&
                      collectionState.items.isEmpty)
                    _buildError(collectionState.error!)
                  else if (collectionState.items.isEmpty)
                    _buildPendingEmpty()
                  else
                    _Entrance(
                      child: PendingPaymentsTable(
                        items: collectionState.items,
                        onView: (c) => context.go(RouteConstants
                            .empCollectionDetails
                            .replaceFirst(':id', c.id)),
                        onRefresh: () async {
                          await ref
                              .read(empCollectionProvider.notifier)
                              .fetch(silent: true);
                          await ref
                              .read(_empPaymentsInCollectionProvider.notifier)
                              .fetch(silent: true);
                        },
                      ),
                    ),
                  if (!collectionState.isLoading &&
                      collectionState.totalPages > 1) ...[
                    const SizedBox(height: 16),
                    _buildCollectionPagination(collectionState),
                  ],
                ] else ...[
                  if (paymentsState.isLoading)
                    _buildLoadingShimmer()
                  else if (paymentsState.error != null &&
                      paymentsState.payments.isEmpty)
                    _buildPaymentError(paymentsState.error!)
                  else if (paymentsState.payments.isEmpty)
                    _buildPaymentEmpty(paymentsState)
                  else
                    _Entrance(
                        child: _buildPaymentsTable(paymentsState.payments)),
                  if (paymentsState.totalPages > 1) ...[
                    const SizedBox(height: 16),
                    _buildPaymentPagination(paymentsState),
                  ],
                ],
              ] else if (isEarlyPayers) ...[
                _buildEarlyPayers(lenderState),
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

    return FilterTabBar(
      dropdownLabel: 'Collections',
      dropdownOptions: _dropdownTabs,
      dropdownValue: dropdownValue,
      onDropdownChanged: (v) => _onTabTap(v),
      pills: _pillTabs.map((t) {
        final isActive = t.key == _activeTab;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterPillTab(def: t, active: isActive, onTap: () => _onTabTap(t.key)),
        );
      }).toList(),
    );
  }

  /// Mga early payer: lender na may verified payment at LAHAT ng bayad ay bago
  /// o eksaktong due date (galing sa `lender_payment_insights` RPC).
  List<UserModel> _earlyPayerLenders(EmpLenderState state) {
    final all = state.lenders.where((u) => u.isEarlyPayer).toList()
      ..sort((a, b) => b.maxDaysEarly.compareTo(a.maxDaysEarly));
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return all;
    return all.where((u) {
      final hay = '${u.firstName} ${u.lastName} ${u.phoneNumber ?? ''} '
              '${u.email ?? ''}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Widget _buildEarlyPayers(EmpLenderState state) {
    if (state.isLoading && state.lenders.isEmpty) return _buildLoadingShimmer();
    final lenders = _earlyPayerLenders(state);
    if (lenders.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const Icon(Icons.bolt_rounded,
                size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              state.lenders.isEmpty
                  ? 'No lenders loaded yet'
                  : 'No early payers found',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 16),
            ),
            if (state.lenders.isNotEmpty && _searchCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.clear_all_rounded, size: 16),
                label: const Text('Clear search'),
              ),
            ],
          ],
        ),
      );
    }
    return _Entrance(
      child: Column(
        children: [
          // Table data (gaya ng ibang Collections tabs) — naka-view at
          // naka-scan ang mga early payer: pangalan, kontak, on-time count,
          // at gaano karaming araw ang aga.
          ResponsiveListCard(
            minTableWidth: 780,
            columns: const [
              ResponsiveCol('Lender', icon: Icons.person_outline, flex: 3),
              ResponsiveCol('Contact', icon: Icons.phone_outlined, flex: 2),
              ResponsiveCol('On Time',
                  icon: Icons.event_available_outlined, flex: 2),
              ResponsiveCol('Early', icon: Icons.bolt_rounded, flex: 2),
            ],
            actionsCol: const ResponsiveActionsCol(width: 110),
            rows: lenders.map((u) => _buildEarlyPayerRow(u)).toList(),
          ),
        ],
      ),
    );
  }

  ResponsiveRow _buildEarlyPayerRow(UserModel u) {
    final fullName = '${u.firstName} ${u.lastName}'.trim();
    return ResponsiveRow(
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fullName.isEmpty ? 'Unnamed lender' : fullName,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
            if ((u.email ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(u.email!,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary),
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
        Text(
          (u.phoneNumber ?? '').isEmpty ? 'No contact' : u.phoneNumber!,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${u.onTimePaymentCount}/${u.verifiedPaymentCount} on time',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: EarlyPayerBadge(daysEarly: u.maxDaysEarly, small: true),
        ),
      ],
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            // Modal (tulad ng People → Lenders) — hindi na lumilipat ng module
            // sa Lender Details page. Nasa modal na ang Payment Profile at ang
            // Early Payer badge, kaya hindi na kailangan umalis sa Collections.
            onTap: () => showUserDetailsModal(context, u),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_outlined,
                      size: 14, color: AppColors.deepNavy),
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
        ],
      ),
    );
  }

  Widget _buildPaymentMethodFilter(_EmpPaymentsState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _paymentMethodTabs.map((t) {
          final isPendingPill = t.key == 'pending_payments';
          final isActive = isPendingPill
              ? _pendingPayments
              : (!_pendingPayments && t.key == state.methodFilter);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterPillTab(
              def: t,
              active: isActive,
              onTap: () {
                if (isPendingPill) {
                  setState(() => _pendingPayments = true);
                  // `status=pending` → lahat ng hindi pa bayad (server-side).
                  ref.read(empCollectionProvider.notifier).setStatus('pending');
                } else {
                  setState(() => _pendingPayments = false);
                  ref
                      .read(_empPaymentsInCollectionProvider.notifier)
                      .setMethod(t.key);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildToolbar(EmpCollectionState cState, _EmpPaymentsState pState, bool isPayments) {
    final isEarlyPayers = _activeTab == 'early_payers';
    final hasSearch = _searchCtrl.text.isNotEmpty;
    final resultsCount = (isPayments && !_pendingPayments)
        ? pState.totalCount
        : isEarlyPayers
            ? _earlyPayerLenders(ref.read(empLenderProvider)).length
            : cState.totalCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: ResponsiveSearchToolbar(
        searchField: Row(
          children: [
            Icon(Icons.search_rounded, size: 18, color: hasSearch ? AppColors.deepNavy : AppColors.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) {
                  if (isEarlyPayers) {
                    setState(() {});
                  } else if (isPayments && !_pendingPayments) {
                    ref
                        .read(_empPaymentsInCollectionProvider.notifier)
                        .setSearch(v);
                  } else {
                    ref.read(empCollectionProvider.notifier).setSearch(v);
                  }
                },
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
                  ref.read(empCollectionProvider.notifier).setSearch('');
                  ref.read(_empPaymentsInCollectionProvider.notifier).setSearch('');
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
              onTap: () => (isPayments && !_pendingPayments)
                  ? ref.read(_empPaymentsInCollectionProvider.notifier).fetch()
                  : ref.read(empCollectionProvider.notifier).fetch(),
            ),
          ],
        ),
        trailing: [
          SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
          SearchResultsChip(count: resultsCount),
        ],
      ),
    );
  }

  Widget _buildCollectionsContent(EmpCollectionState state) {
    final items = state.items;
    if (items.isEmpty) {
      final isFiltered = state.search.isNotEmpty || state.statusFilter != 'all';
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
            OutlinedButton.icon(onPressed: () { _searchCtrl.clear(); ref.read(empCollectionProvider.notifier).setSearch(''); ref.read(empCollectionProvider.notifier).setStatus('all'); }, icon: const Icon(Icons.clear_all_rounded, size: 16), label: const Text('Clear filters')),
          ]),
        );
      }
      return _buildEmpty();
    }
    return _Entrance(
      child: Column(
        children: [
          ResponsiveListCard(
            minTableWidth: 820,
            columns: const [
              ResponsiveCol('Lender & Loan', icon: Icons.person_outline, flex: 3),
              ResponsiveCol('Amount', icon: Icons.payments_outlined, flex: 2),
              ResponsiveCol('Rider', icon: Icons.delivery_dining_outlined, flex: 2),
              ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 2),
            ],
            actionsCol: const ResponsiveActionsCol(width: 240),
            rows: items.map((e) => _buildCollectionRow(e)).toList(),
          ),
        ],
      ),
    );
  }

  ResponsiveRow _buildCollectionRow(dynamic col) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final schedule = col.loanSchedule as Map<String, dynamic>? ?? {};
    final isOffice = col.collectionType == 'office';
    final amount = col.amountCollected ?? (schedule['amount_due'] as num?)?.toDouble() ?? 0.0;
    final status = (col.status?.toString() ?? '').toLowerCase();
    final accent = _accentForStatus(status);
    final canAssign = col.status == 'requested' && !isOffice;
    // Rejected = hindi nakuha ang pera. Kailangang mag-assign ng rider na
    // mangolekta muli (bagong assignment para sa parehong schedule).
    final canReassign = status == 'rejected' && !isOffice;
    // Nag-submit na si rider ng proof — kailangang i-approve (baba ang loan
    // balance) o i-reject (hindi nakuha ang pera).
    final canReview = status == 'pending_approval';
    return ResponsiveRow(
      cells: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(col.loanNumber.isNotEmpty ? col.loanNumber : '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(col.lenderName.isNotEmpty ? col.lenderName : 'Unknown lender', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary), overflow: TextOverflow.ellipsis),
        ]),
        Text('₱${fmt.format(amount)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: amount > 0 ? AppColors.deepNavy : AppColors.textSecondary)),
        Row(children: [Icon(isOffice ? Icons.storefront_rounded : Icons.delivery_dining_rounded, size: 14, color: AppColors.textTertiary), const SizedBox(width: 6), Flexible(child: Text(isOffice ? 'Office' : (col.riderName.isNotEmpty ? col.riderName : '—'), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis))]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(child: Text(status.split('_').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '').join(' '), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent), overflow: TextOverflow.ellipsis)),
        ]),
      ],
      actions: Row(mainAxisSize: MainAxisSize.min, children: [
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
        if (canReassign) const SizedBox(width: 6),
        if (canReassign)
          InkWell(
            onTap: () async {
              final loanScheduleId = col.loanScheduleId as String? ?? '';
              final loanId = (col.loanSchedule?['loan']?['id'] as String?) ?? (col.loanSchedule?['loan_id'] as String?) ?? '';
              final result = await showDialog<bool>(context: context, builder: (_) => EmpAssignRiderModal(loanScheduleId: loanScheduleId, loanId: loanId));
              if (result == true && mounted) context.showSnackBarAsToast(const SnackBar(content: Text('Rider assigned successfully'), backgroundColor: AppColors.success));
            },
            borderRadius: BorderRadius.circular(9),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(9)), child: const Text('Reassign', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
          ),
        // Approve / Reject direktang sa action column kapag na-submit na ni
        // rider ang collection. Silent ang refresh ng provider kaya HINDI
        // nag-reloading nang buo ang table (realtime din ang listahan).
        if (canReview) ...[
          const SizedBox(width: 6),
          _CollectionActionButton(
            label: 'Approve',
            color: AppColors.success,
            busy: _reviewingId == col.id,
            onTap: () => _reviewCollection(col, approve: true),
          ),
          const SizedBox(width: 6),
          _CollectionActionButton(
            label: 'Reject',
            color: AppColors.error,
            busy: _reviewingId == col.id,
            onTap: () => _reviewCollection(col, approve: false),
          ),
        ],
        InkWell(
          onTap: () => context.go(RouteConstants.empCollectionDetails.replaceFirst(':id', col.id)),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.visibility_outlined, size: 14, color: AppColors.deepNavy), SizedBox(width: 4), Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.deepNavy))])),
        ),
      ]),
    );
  }

  /// Approve o Reject ang rider-submitted collection. Hindi ito nag-shishimmer
  /// ng buong table — silent refresh ang approve/reject sa provider.
  Future<void> _reviewCollection(dynamic col, {required bool approve}) async {
    final assignmentId = col.id as String? ?? '';
    if (assignmentId.isEmpty) return;

    var reason = '';
    if (!approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reject Collection'),
          content: TextField(
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Reason for rejection (required)',
            ),
            onChanged: (v) => reason = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (reason.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              child: const Text('Reject',
                  style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final notifier = ref.read(empCollectionProvider.notifier);
    setState(() => _reviewingId = assignmentId);
    bool ok;
    try {
      ok = approve
          ? await notifier.approveCollection(assignmentId)
          : await notifier.rejectCollection(assignmentId, reason.trim());
    } finally {
      if (mounted) setState(() => _reviewingId = null);
    }
    if (!mounted) return;
    context.showSnackBarAsToast(
      SnackBar(
        content: Text(ok
            ? (approve
                ? 'Collection approved — loan balance updated'
                : 'Collection rejected — rider can be reassigned')
            : (ref.read(empCollectionProvider).error ??
                (approve
                    ? 'Failed to approve collection'
                    : 'Failed to reject collection'))),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  Widget _buildPaymentsTable(List<Map<String, dynamic>> payments) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final dateFmt = DateFormat('MMM dd, yyyy h:mm a');
    return ResponsiveListCard(
      minTableWidth: 900,
      columns: const [
        ResponsiveCol('Lender & Loan', icon: Icons.person_outline, flex: 3),
        ResponsiveCol('Amount', icon: Icons.payments_outlined, flex: 2),
        ResponsiveCol('Method', icon: Icons.account_balance_wallet_outlined, flex: 2),
        ResponsiveCol('Date', icon: Icons.event_outlined, flex: 2),
        ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 2),
      ],
      actionsCol: const ResponsiveActionsCol(width: 96),
      rows: payments.map((p) {
        final lender = p['lender'] as Map<String, dynamic>? ?? {};
        final loan = p['loan'] as Map<String, dynamic>? ?? {};
        final status = (p['status'] as String? ?? '-').toLowerCase();
        final method = (p['payment_method'] as String? ?? p['method'] as String? ?? '-').toLowerCase();
        final amt = (p['amount'] as num?)?.toDouble() ?? 0;
        final statusColor = status == 'verified' ? AppColors.success : status == 'pending' ? AppColors.warning : AppColors.error;
        final dateStr = () {
          final d = p['created_at'];
          if (d == null) return '-';
          try { return dateFmt.format(toManila(DateTime.parse(d.toString()))); } catch (_) { return d.toString(); }
        }();
        final flatLenderName = p['lender_name'] != null ? p['lender_name'] as String : null;
        final resolvedLender = flatLenderName != null && flatLenderName.isNotEmpty
            ? flatLenderName
            : ('${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim().isEmpty ? '—' : '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim());
        final loanNumberFlat = p['loan_number'] as String? ?? loan['loan_number'] as String? ?? '—';
        return ResponsiveRow(
          cells: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(resolvedLender, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(loanNumberFlat, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ]),
            Text('₱${fmt.format(amt)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            _PaymentMethodInline(method: method),
            Text(dateStr, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(child: Text(status.split('_').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '').join(' '), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor), overflow: TextOverflow.ellipsis)),
            ]),
          ],
          actions: status == 'verified'
              ? InkWell(
                  onTap: () => _confirmReverse(p['id'] as String? ?? ''),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.error.withValues(alpha: 0.5))), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.undo_rounded, size: 14, color: AppColors.error), SizedBox(width: 4), Text('Reverse', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.error))])),
                )
              : InkWell(
                  onTap: () {
                    final id = p['id'] as String? ?? '';
                    if (id.isNotEmpty) context.go(RouteConstants.empPaymentDetails.replaceFirst(':id', id));
                  },
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.visibility_outlined, size: 14, color: AppColors.deepNavy), SizedBox(width: 4), Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.deepNavy))])),
                ),
        );
      }).toList(),
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
      case 'pending_approval':
        return AppColors.warning;
      case 'completed':
        return AppColors.riderGreen;
      case 'rejected':
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

  /// Walang pending na babayaran — lahat ng koleksyon ay tapos na.
  Widget _buildPendingEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
                color: Color(0x08000000),
                blurRadius: 12,
                offset: Offset(0, 4))
          ]),
      child: Column(children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border)),
          child: const Icon(Icons.task_alt_rounded,
              size: 34, color: AppColors.success),
        ),
        const SizedBox(height: 16),
        const Text('No pending payments',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'All installments are paid, or there is no open collection request.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => ref.read(empCollectionProvider.notifier).fetch(),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh'),
        ),
      ]),
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
    final isFiltered = state.search.isNotEmpty || state.methodFilter != 'all';
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




/// Maliit na pill-style button para sa Approve / Reject sa actions column.
class _CollectionActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  /// True habang tumatakbo ang request — spinner sa halip na label.
  final bool busy;
  const _CollectionActionButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: busy ? color.withValues(alpha: 0.7) : color,
          borderRadius: BorderRadius.circular(9),
        ),
        child: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
      ),
    );
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
