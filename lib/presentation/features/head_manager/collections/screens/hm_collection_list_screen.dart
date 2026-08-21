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
                  'requested',
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
                    ? (state.error != null
                        ? _buildError(context, ref, state.error!)
                        : _buildEmpty())
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
          key: ValueKey(col.id),
          collection: col,
          fmt: fmt,
          onTap: () => context.go(
            RouteConstants.hmCollectionDetails.replaceFirst(':id', col.id),
          ),
        );
      },
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            const Text('Failed to load collections',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => ref.read(hmCollectionProvider.notifier).fetch(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
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
      {super.key, required this.collection, required this.fmt, required this.onTap});

  @override
  State<_CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<_CollectionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final col = widget.collection;
    final schedule = col.loanSchedule as Map<String, dynamic>? ?? {};
    final isOffice = col.collectionType == 'office';
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
            color: _hover
                ? AppColors.deepNavy.withValues(alpha: 0.02)
                : Colors.white,
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
                child: Icon(
                    isOffice
                        ? Icons.storefront_outlined
                        : Icons.local_shipping_outlined,
                    color: AppColors.riderGreen,
                    size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Lender identity is the primary info staff need to
                    // dispatch a rider — who requested, for which loan.
                    Text(
                      col.lenderName.isNotEmpty ? col.lenderName : 'Unknown lender',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      col.loanNumber.isNotEmpty ? col.loanNumber : '—',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(isOffice
                            ? Icons.storefront_outlined
                            : Icons.delivery_dining_outlined,
                            size: 13, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            isOffice
                                ? 'Office visit payment'
                                : col.riderName.isNotEmpty
                                    ? col.riderName
                                    : 'Unassigned',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₱${widget.fmt.format(amount)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                ],
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
