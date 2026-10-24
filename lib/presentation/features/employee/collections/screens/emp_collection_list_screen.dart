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
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/details/user_details_modal.dart';
import '../../../../shared/widgets/early_payer_badge.dart';
import '../../../../shared/widgets/filter_pill_tab.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../../head_manager/lenders/providers/hm_lender_provider.dart';
import '../../../head_manager/collections/providers/hm_collection_provider.dart';
import '../../../head_manager/payments/widgets/payment_details_modal.dart';
import '../../../head_manager/collections/widgets/assign_rider_collection_modal.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

// ── Payments state reused inside Collections (so Payments tab lives here) ──
class _PaymentsState {
  final List<Map<String, dynamic>> payments;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final String methodFilter;
  final String? dateFrom;
  final String? dateTo;
  const _PaymentsState({
    this.payments = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.methodFilter = 'all',
    this.dateFrom,
    this.dateTo,
  });
  _PaymentsState copyWith({
    List<Map<String, dynamic>>? payments,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    String? methodFilter,
    String? dateFrom,
    String? dateTo,
  }) =>
      _PaymentsState(
        payments: payments ?? this.payments,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        totalCount: totalCount ?? this.totalCount,
        methodFilter: methodFilter ?? this.methodFilter,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );
}

class _PaymentsNotifier extends StateNotifier<_PaymentsState>
    with RealtimeRefreshMixin {
  final PaymentRemoteDataSource _ds;
  _PaymentsNotifier(this._ds) : super(const _PaymentsState()) {
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
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
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

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
    fetch();
  }

  Future<bool> reversePayment(String paymentId) async {
    try {
      await _ds.reversePayment(paymentId: paymentId, reason: 'Reversed by Head Manager');
      await fetch();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final _hmPaymentsInCollectionProvider =
    StateNotifierProvider<_PaymentsNotifier, _PaymentsState>((ref) {
  return _PaymentsNotifier(sl<PaymentRemoteDataSource>());
});

class EmpCollectionListScreen extends ConsumerStatefulWidget {
  const EmpCollectionListScreen({super.key});

  @override
  ConsumerState<EmpCollectionListScreen> createState() => _EmpCollectionListScreenState();
}

class _EmpCollectionListScreenState extends ConsumerState<EmpCollectionListScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  DateTimeRange? _dateRange;

  /// Status ng COLLECTIONS dropdown (all, requested, assigned, ...). Ang
  /// Payments / Early Payers ay hindi na local state — galing na sa URL
  /// (`/hm/collections/payments`, `/hm/collections/early-payers`).
  String _activeTab = 'all';

  /// Huling na-load na tab — para hindi umulit ang fetch sa bawat rebuild.
  String? _lastRouteTab;

  final _dropdownTabs = const [
    FilterTabDef('all', 'All', Icons.layers_outlined),
    FilterTabDef('requested', 'Requested', Icons.hourglass_top_rounded),
    FilterTabDef('assigned', 'Assigned', Icons.assignment_ind_outlined),
    FilterTabDef('in_progress', 'In Progress', Icons.sync_rounded),
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
    FilterTabDef('office_cash', 'Office', Icons.storefront_rounded),
    FilterTabDef('rider_collection', 'Cash on Delivery', Icons.delivery_dining_rounded),
    // `gcash_xendit` ang aktwal na `payment_method` ng Xendit payments sa DB —
    // kung `gcash` lang ang ipapasa, walang tugmang row at "No matching
    // payments" ang lumalabas kahit may bayad na.
    FilterTabDef('gcash_xendit', 'GCash', Icons.phone_android_rounded),
  ];

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    final from = r == null ? null : SearchDateFilter.fromParam(r.start);
    final to = r == null ? null : SearchDateFilter.toParam(r.end);
    ref.read(hmCollectionProvider.notifier).setDateRange(from, to);
    ref.read(_hmPaymentsInCollectionProvider.notifier).setDateRange(from, to);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Tab mula sa kasalukuyang URL — ang URL ang source of truth.
  static String _tabFromPath(String path) {
    if (path == RouteConstants.hmCollectionPayments) return 'payments';
    if (path == RouteConstants.hmCollectionEarlyPayers) return 'early_payers';
    return 'all';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tab = _tabFromPath(GoRouterState.of(context).uri.path);
    if (tab == _lastRouteTab) return;
    final isFirst = _lastRouteTab == null;
    _lastRouteTab = tab;
    // Unang build: may sariling initial fetch ang bawat provider, kaya huwag
    // nang mag-doble. Sa pagpalit ng tab (URL), dito naglo-load ng tamang data.
    if (isFirst) return;
    _searchCtrl.clear();
    if (tab == 'payments') {
      ref.read(_hmPaymentsInCollectionProvider.notifier).fetch(method: 'all');
    } else if (tab == 'early_payers') {
      // Lender list na may `is_early_payer` insight — client-side na search.
      ref.read(hmLenderProvider.notifier).load(silent: true);
    }
  }

  void _onTabTap(String key) {
    // Payments / Early Payers: URL ang nagbibiyahe sa tab.
    if (key == 'payments' || key == 'early_payers') {
      final target = key == 'payments'
          ? RouteConstants.hmCollectionPayments
          : RouteConstants.hmCollectionEarlyPayers;
      if (GoRouterState.of(context).uri.path == target) return;
      _searchCtrl.clear();
      context.go(target);
      return;
    }

    if (key == _activeTab) return;
    setState(() => _activeTab = key);
    _searchCtrl.clear();
    ref.read(hmCollectionProvider.notifier).setSearch('');
    ref.read(hmCollectionProvider.notifier).setStatus(key);
  }

  @override
  Widget build(BuildContext context) {
    final collectionState = ref.watch(hmCollectionProvider);
    final paymentsState = ref.watch(_hmPaymentsInCollectionProvider);
    final lenderState = ref.watch(hmLenderProvider);
    final tab = _tabFromPath(GoRouterState.of(context).uri.path);
    final isPayments = tab == 'payments';
    final isEarlyPayers = tab == 'early_payers';

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
              _buildTabPills(tab),
              const SizedBox(height: 16),
              _buildToolbar(
                  collectionState, paymentsState, isPayments, isEarlyPayers),
              const SizedBox(height: 16),
              if (isPayments) ...[
                _buildPaymentMethodFilter(paymentsState),
                const SizedBox(height: 12),
                if (paymentsState.isLoading)
                  _buildLoadingShimmer()
                else if (paymentsState.error != null &&
                    paymentsState.payments.isEmpty)
                  _buildPaymentError(paymentsState.error!)
                else if (_filteredPayments(paymentsState.payments).isEmpty)
                  _buildPaymentEmpty(paymentsState)
                else
                  _Entrance(
                      child: _buildPaymentsTable(
                          _filteredPayments(paymentsState.payments))),
                if (paymentsState.totalPages > 1) ...[
                  const SizedBox(height: 16),
                  _buildPaymentPagination(paymentsState),
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

  // ── Tabs: dropdown for All/Requested/etc (like Loan Records Pipeline) + Payments pill beside it ──
  Widget _buildTabPills(String tab) {
    final dropdownKeys = _dropdownTabs.map((e) => e.key).toSet();
    // Sa Payments / Early Payers tab, walang value ang Collections dropdown.
    final dropdownValue = tab == 'all' && dropdownKeys.contains(_activeTab)
        ? _activeTab
        : null;

    return FilterTabBar(
      dropdownLabel: 'Collections',
      dropdownOptions: _dropdownTabs,
      dropdownValue: dropdownValue,
      onDropdownChanged: (v) => _onTabTap(v),
      pills: _pillTabs.map((t) {
        final isActive = t.key == tab;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterPillTab(def: t, active: isActive, onTap: () => _onTabTap(t.key)),
        );
      }).toList(),
    );
  }

  /// Mga early payer: lender na may verified payment at LAHAT ng bayad ay bago
  /// o eksaktong due date. Galing sa `lender_payment_insights` RPC (hindi
  /// kailangang mag-compute sa client).
  List<UserModel> _earlyPayerLenders(HmLenderState state) {
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

  Widget _buildEarlyPayers(HmLenderState state) {
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

  Widget _buildPaymentMethodFilter(_PaymentsState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _paymentMethodTabs.map((t) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterPillTab(
              def: t,
              active: t.key == state.methodFilter,
              onTap: () => ref
                  .read(_hmPaymentsInCollectionProvider.notifier)
                  .setMethod(t.key),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Toolbar: single outer box with Search (hint "Search"), refresh, results badge ──
  Widget _buildToolbar(HmCollectionState cState, _PaymentsState pState,
          bool isPayments, bool isEarlyPayers) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ResponsiveSearchToolbar(
          searchField: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: isPayments
                ? 'Search payments...'
                : isEarlyPayers
                    ? 'Search early payers...'
                    : 'Search collections...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) {
              if (isPayments || isEarlyPayers) {
                setState(() {});
              } else {
                ref.read(hmCollectionProvider.notifier).setSearch(v);
              }
            },
          ),
          trailing: [
            SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
            SearchResultsChip(
              count: isPayments
                  // No search text -> true server total; while searching the
                  // box filters client-side so the chip matches what is shown.
                  ? (_searchCtrl.text.trim().isEmpty
                      ? pState.totalCount
                      : _filteredPayments(pState.payments).length)
                  : isEarlyPayers
                      ? _earlyPayerLenders(ref.read(hmLenderProvider)).length
                      : cState.totalCount,
            ),
          ],
        ),
      );



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

  // ── Collections content ──
  Widget _buildCollectionsContent(HmCollectionState state) {
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
            OutlinedButton.icon(onPressed: () { _searchCtrl.clear(); ref.read(hmCollectionProvider.notifier).setSearch(''); ref.read(hmCollectionProvider.notifier).setStatus('all'); }, icon: const Icon(Icons.clear_all_rounded, size: 16), label: const Text('Clear filters')),
          ]),
        );
      }
      return _buildEmpty();
    }
    return _Entrance(
      child: Column(
        children: [
          // Premium header + cards wrapped in white card
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
    // AMOUNT NA HININGI ng lender (`requested_amount`) — hindi ang naka-default
    // na installment amount. Hal. ₱200 ang due pero ₱5,000 ang hininging bayad
    // (partial/advance) — ₱5,000 dapat ang lumabas dito, kapareho ng nasa
    // notification ("requested a rider to collect of ₱5,000"). Ang
    // `amount_collected` ang mas tumpak kapag may naitala nang koleksyon.
    final amount = col.amountCollected ??
        col.requestedAmount ??
        (schedule['amount_due'] as num?)?.toDouble() ??
        0.0;
    final status = (col.status?.toString() ?? '').toLowerCase();
    final accent = _accentForStatus(status);
    final canAssign = col.status == 'requested' && !isOffice;
    // Rejected = hindi nakuha ang pera. Kailangang mag-assign ng rider na
    // mangolekta muli (bagong assignment para sa parehong schedule).
    final canReassign = status == 'rejected' && !isOffice;
    return ResponsiveRow(
      cells: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(col.loanNumber.isNotEmpty ? col.loanNumber : 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(col.lenderName.isNotEmpty ? col.lenderName : 'Unknown lender', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary), overflow: TextOverflow.ellipsis),
        ]),
        Text('₱${fmt.format(amount)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: amount > 0 ? AppColors.deepNavy : AppColors.textSecondary)),
        Row(children: [Icon(isOffice ? Icons.storefront_rounded : Icons.delivery_dining_rounded, size: 14, color: AppColors.textTertiary), const SizedBox(width: 6), Flexible(child: Text(isOffice ? 'Office' : (col.riderName.isNotEmpty ? col.riderName : 'N/A'), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis))]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(child: Text(status.split('_').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '').join(' '), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent), overflow: TextOverflow.ellipsis)),
        ]),
      ],
      actions: Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: () => context.go(RouteConstants.empCollectionDetails.replaceFirst(':id', col.id)),
          borderRadius: BorderRadius.circular(8),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.visibility_outlined, size: 14, color: AppColors.deepNavy), SizedBox(width: 4), Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.deepNavy))])),
        ),
        // "Assign" — dating rider icon button, ginawang text button at inilagay
        // sa kanan ng View. Requested (hindi pa naka-assign) lang ito lumalabas.
        if (canAssign) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: () async {
              final loanScheduleId = col.loanScheduleId as String? ?? '';
              final loanId = (col.loanSchedule?['loan']?['id'] as String?) ?? (col.loanSchedule?['loan_id'] as String?) ?? '';
              final result = await showDialog<bool>(context: context, builder: (_) => AssignRiderCollectionModal(loanScheduleId: loanScheduleId, loanId: loanId, assignmentId: col.id as String? ?? ''));
              if (result == true && mounted) context.showSnackBarAsToast(const SnackBar(content: Text('Rider assigned successfully'), backgroundColor: AppColors.success));
            },
            borderRadius: BorderRadius.circular(9),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: AppColors.riderGreen, borderRadius: BorderRadius.circular(9)), child: const Text('Assign', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
          ),
        ],
        if (canReassign) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: () async {
              final loanScheduleId = col.loanScheduleId as String? ?? '';
              final loanId = (col.loanSchedule?['loan']?['id'] as String?) ?? (col.loanSchedule?['loan_id'] as String?) ?? '';
              final result = await showDialog<bool>(context: context, builder: (_) => AssignRiderCollectionModal(loanScheduleId: loanScheduleId, loanId: loanId));
              if (result == true && mounted) context.showSnackBarAsToast(const SnackBar(content: Text('Rider assigned successfully'), backgroundColor: AppColors.success));
            },
            borderRadius: BorderRadius.circular(9),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(9)), child: const Text('Reassign', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
          ),
        ],
      ]),
    );
  }

  // ── Payments table (premium container like loan records) ──
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
        final method = (p['payment_method'] as String? ?? '-').toLowerCase();
        final amt = (p['amount'] as num?)?.toDouble() ?? 0;
        final statusColor = status == 'verified' ? AppColors.success : status == 'pending' ? AppColors.warning : AppColors.error;
        final dateStr = () {
          final d = p['created_at'];
          if (d == null) return '-';
          try { return dateFmt.format(toManila(DateTime.parse(d.toString()))); } catch (_) { return d.toString(); }
        }();
        // Petsa AT ORAS ng bayad na nag-settle ng dating overdue (`paid_at`,
        // fallback sa `created_at`) — ito ang kasama sa "Overdue paid" tag.
        final overduePaidStr = () {
          final d = p['paid_at'] ?? p['created_at'];
          if (d == null) return '';
          try { return dateFmt.format(toManila(DateTime.parse(d.toString()))); } catch (_) { return ''; }
        }();
        return ResponsiveRow(
          cells: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim().isEmpty ? '—' : '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(loan['loan_number'] as String? ?? '—', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ]),
            Text('₱${fmt.format(amt)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            _PaymentMethodInline(method: method),
            Text(dateStr, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(paymentStatusLabel(status), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor), overflow: TextOverflow.ellipsis)),
                ]),
                // Bayad ang isang lampas nang installment? Ipakita sa ilalim ng
                // status para makita ng staff na overdue payment ito — galing
                // sa `paid_overdue` ng `payments-view?fn=get-list`.
                if (p['paid_overdue'] == true) ...[
                  const SizedBox(height: 4),
                  Text(
                      overduePaidStr.isEmpty ? 'Overdue paid' : 'Overdue paid · $overduePaidStr',
                      maxLines: 2,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success),
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
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
                    if (id.isNotEmpty) showPaymentDetailsModal(context, id);
                  },
                  borderRadius: BorderRadius.circular(8),
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
      final ok = await ref.read(_hmPaymentsInCollectionProvider.notifier).reversePayment(paymentId);
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
          ElevatedButton.icon(onPressed: () => ref.read(hmCollectionProvider.notifier).fetch(), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Retry'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.deepNavy, foregroundColor: Colors.white)),
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
          ElevatedButton.icon(onPressed: () => ref.read(_hmPaymentsInCollectionProvider.notifier).fetch(), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Retry'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.deepNavy, foregroundColor: Colors.white)),
        ]),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.delivery_dining_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          SizedBox(height: 16),
          Text(
            'No collections found',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentEmpty(_PaymentsState state) {
    final isFiltered = _searchCtrl.text.isNotEmpty || state.methodFilter != 'all';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltered ? Icons.search_off_rounded : Icons.payments_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'No matching payments' : 'No payments found',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () {
                _searchCtrl.clear();
                ref.read(_hmPaymentsInCollectionProvider.notifier).setMethod('all');
                setState(() {});
              },
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCollectionPagination(HmCollectionState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        const Spacer(),
        _PageBtn(icon: Icons.chevron_left_rounded, enabled: state.currentPage > 1, onTap: () => ref.read(hmCollectionProvider.notifier).fetch(page: state.currentPage - 1)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(20)), child: Text('${state.currentPage} / ${state.totalPages}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
        const SizedBox(width: 8),
        _PageBtn(icon: Icons.chevron_right_rounded, enabled: state.currentPage < state.totalPages, onTap: () => ref.read(hmCollectionProvider.notifier).fetch(page: state.currentPage + 1)),
      ]),
    );
  }

  Widget _buildPaymentPagination(_PaymentsState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        const Spacer(),
        _PageBtn(icon: Icons.chevron_left_rounded, enabled: state.currentPage > 1, onTap: () => ref.read(_hmPaymentsInCollectionProvider.notifier).fetch(page: state.currentPage - 1)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(20)), child: Text('${state.currentPage} / ${state.totalPages}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
        const SizedBox(width: 8),
        _PageBtn(icon: Icons.chevron_right_rounded, enabled: state.currentPage < state.totalPages, onTap: () => ref.read(_hmPaymentsInCollectionProvider.notifier).fetch(page: state.currentPage + 1)),
      ]),
    );
  }
}

// ── Supporting widgets (mirrors loan records style) ──


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
