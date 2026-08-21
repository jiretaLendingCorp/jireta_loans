// lib/presentation/features/employee/collections/screens/emp_collection_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/tables/table_filter_bar.dart';
import '../../../../shared/widgets/tables/table_pagination.dart';
import '../providers/emp_collection_provider.dart';

class EmpCollectionListScreen extends ConsumerStatefulWidget {
  const EmpCollectionListScreen({super.key});

  @override
  ConsumerState<EmpCollectionListScreen> createState() =>
      _EmpCollectionListScreenState();
}

class _EmpCollectionListScreenState
    extends ConsumerState<EmpCollectionListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  int _currentPage = 1;

  final _tabs = [
    ('all', 'All'),
    ('requested', 'Requested'),
    ('assigned', 'Assigned'),
    ('accepted', 'Accepted'),
    ('in_progress', 'In Progress'),
    ('completed', 'Completed'),
    ('failed', 'Failed'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(empCollectionListProvider.notifier).loadList();
    });
  }

  void _onTabChanged() {
    if (_tabCtrl.indexIsChanging) return;
    _currentPage = 1;
    ref.read(empCollectionListProvider.notifier).loadList(
        status: _tabs[_tabCtrl.index].$1 == 'all'
            ? null
            : _tabs[_tabCtrl.index].$1);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empCollectionListProvider);
    final items = state.valueOrNull?['items'] as List? ?? [];
    final total = state.valueOrNull?['total'] as int? ?? 0;
    final totalPages = (total / 20).ceil();

    return WebScaffold(
      title: 'Collections',
      actions: [
        IconButton(
          onPressed: () => ref
              .read(empCollectionListProvider.notifier)
              .loadList(
                  status: _tabs[_tabCtrl.index].$1 == 'all'
                      ? null
                      : _tabs[_tabCtrl.index].$1),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          tooltip: 'Refresh',
        ),
      ],
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              labelColor: AppColors.deepNavy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
            ),
          ),
          buildFilterBar(
            searchController: _searchCtrl,
            searchHint: 'Search by loan# or lender name...',
            onSearch: (q) => ref
                .read(empCollectionListProvider.notifier)
                .loadList(
                    status: _tabs[_tabCtrl.index].$1 == 'all'
                        ? null
                        : _tabs[_tabCtrl.index].$1),
            filters: const [],
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.hasError
                    ? _buildError(context)
                    : items.isEmpty
                        ? const EmptyStateWidget(
                            icon: Icons.local_shipping_outlined,
                            title: 'No collections found',
                            subtitle: 'Assign a rider to begin collection.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, i) => _CollectionCard(
                              key: ValueKey(items[i]['id']),
                              collection: items[i],
                            ),
                          ),
          ),
          if (totalPages > 1)
            TablePagination(
              currentPage: _currentPage,
              totalPages: totalPages,
              totalCount: total,
              onPageChange: (p) {
                _currentPage = p;
                ref.read(empCollectionListProvider.notifier).loadList(
                    status: _tabs[_tabCtrl.index].$1 == 'all'
                        ? null
                        : _tabs[_tabCtrl.index].$1,
                    page: p);
              },
            ),
        ],
      ),
    );
  }
  Widget _buildError(BuildContext context) {
    final state = ref.watch(empCollectionListProvider);
    final message =
        ErrorHandler.handle(state.error).message;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            const Text(
              'Failed to load collections',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => ref
                  .read(empCollectionListProvider.notifier)
                  .loadList(
                      status: _tabs[_tabCtrl.index].$1 == 'all'
                          ? null
                          : _tabs[_tabCtrl.index].$1),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionCard extends ConsumerWidget {
  final Map<String, dynamic> collection;
  const _CollectionCard({super.key, required this.collection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final id = collection['id'] as String? ?? '';
    final loanNumber = collection['loan_number'] ??
        collection['loans']?['loan_number'] ??
        '-';
    final lenderProf = collection['loans']?['lender_profiles'];
    final lenderUsers = lenderProf?['users'];
    final lenderName = collection['lender_name'] ??
        '${lenderUsers?['first_name'] ?? ''} ${lenderUsers?['last_name'] ?? ''}'
            .trim();
    final riderUsers = collection['rider']?['users'];
    final riderName = (collection['rider_name'] ??
            '${riderUsers?['first_name'] ?? ''} ${riderUsers?['last_name'] ?? ''}'
                .trim())
        .toString()
        .isEmpty
        ? 'Unassigned'
        : collection['rider_name'] ??
            '${riderUsers?['first_name'] ?? ''} ${riderUsers?['last_name'] ?? ''}'
                .trim();
    final status = collection['status'] as String? ?? 'assigned';
    final collectionType =
        collection['collection_type'] as String? ?? 'rider';
    final isOffice = collectionType == 'office';
    final amount = (collection['amount_due'] as num?)?.toDouble() ??
        (collection['loan_schedule']?['amount_due'] as num?)?.toDouble() ??
        0.0;
    final schedule = collection['collection_schedule'] as String?;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(
          RouteConstants.empCollectionDetails.replaceFirst(':id', id),
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
                child: Icon(
                    isOffice
                        ? Icons.storefront_outlined
                        : Icons.local_shipping_outlined,
                    color: AppColors.deepNavy,
                    size: 22),
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
                    const SizedBox(height: 2),
                    Text(lenderName,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                    Text(isOffice ? 'Office visit payment' : 'Rider: $riderName',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textTertiary)),
                    if (schedule != null)
                      Text('Schedule: $schedule',
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
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right,
                      color: AppColors.textTertiary, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
