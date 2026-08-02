// lib/presentation/features/head_manager/collections/screens/hm_collection_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/tables/table_filter_bar.dart';
import '../../../../shared/widgets/tables/table_pagination.dart';
import '../providers/hm_collection_provider.dart';

class HmCollectionListScreen extends ConsumerWidget {
  const HmCollectionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hmCollectionProvider);

    return WebScaffold(
      title: 'Collections',
      actions: [
        IconButton(
          onPressed: () => ref.read(hmCollectionProvider.notifier).fetch(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
        ),
      ],
      body: Column(
        children: [
          buildFilterBar(
            searchController: TextEditingController(),
            searchHint: 'Search by loan# or lender...',
            filters: [
              (
                label: 'Status',
                value: state.statusFilter,
                options: [
                  'all',
                  'assigned',
                  'accepted',
                  'declined',
                  'in_progress',
                  'completed',
                  'failed'
                ],
                onChanged: (v) =>
                    ref.read(hmCollectionProvider.notifier).setStatus(v),
              ),
            ],
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.items.isEmpty
                    ? _buildEmpty()
                    : _buildList(context, state),
          ),
          if (state.totalPages > 1)
            TablePagination(
              currentPage: state.currentPage,
              totalPages: state.totalPages,
              totalCount: state.totalCount,
              onPageChange: (p) =>
                  ref.read(hmCollectionProvider.notifier).fetch(page: p),
            ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, HmCollectionState state) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final col = state.items[i];
        return _CollectionCard(
          collection: col,
          fmt: fmt,
          onTap: () => context.go(
            RouteConstants.hmCollectionDetails.replaceFirst(':id', col.id),
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_shipping_outlined,
              size: 64, color: AppColors.textTertiary),
          SizedBox(height: 16),
          Text('No collections found',
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _CollectionCard extends StatefulWidget {
  final dynamic collection;
  final NumberFormat fmt;
  final VoidCallback onTap;
  const _CollectionCard(
      {required this.collection, required this.fmt, required this.onTap});

  @override
  State<_CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<_CollectionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final col = widget.collection;
    final schedule = col.loanSchedule as Map<String, dynamic>? ?? {};
    final rider = col.rider as Map<String, dynamic>? ?? {};
    final amount = col.amountCollected ??
        (schedule['amount_due'] as num?)?.toDouble() ??
        0.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hover ? AppColors.deepNavy.withValues(alpha: 0.02) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _hover
                    ? AppColors.deepNavy.withValues(alpha: 0.2)
                    : AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hover ? 0.05 : 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.riderGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_shipping_outlined,
                    color: AppColors.riderGreen, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₱${widget.fmt.format(amount)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.delivery_dining_outlined,
                            size: 13, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          rider.isNotEmpty
                              ? '${rider['first_name']} ${rider['last_name']}'
                              : 'Unassigned',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (col.collectionSchedule != null) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.calendar_today_outlined,
                              size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM d, y')
                                .format(col.collectionSchedule!),
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              StatusBadge(status: col.status),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
