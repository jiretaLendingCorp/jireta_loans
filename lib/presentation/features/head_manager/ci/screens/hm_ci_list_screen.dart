// lib/presentation/features/head_manager/ci/screens/hm_ci_list_screen.dart
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
import '../providers/hm_ci_provider.dart';

class HmCiListScreen extends ConsumerStatefulWidget {
  const HmCiListScreen({super.key});

  @override
  ConsumerState<HmCiListScreen> createState() => _HmCiListScreenState();
}

class _HmCiListScreenState extends ConsumerState<HmCiListScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmCiProvider);

    return WebScaffold(
      title: 'Credit Investigations',
      actions: [
        IconButton(
          onPressed: () => ref.read(hmCiProvider.notifier).fetch(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
        ),
      ],
      body: Column(
        children: [
          buildFilterBar(
            searchController: _search,
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
                  'completed'
                ],
                onChanged: (v) => ref.read(hmCiProvider.notifier).setStatus(v),
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
                  ref.read(hmCiProvider.notifier).fetch(page: p),
            ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, HmCiState state) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final ci = state.items[i];
        return _CiCard(
          ci: ci,
          onTap: () => context.go(
            RouteConstants.hmCiDetails.replaceFirst(':id', ci.id),
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
          Icon(Icons.search_off_outlined,
              size: 64, color: AppColors.textTertiary),
          SizedBox(height: 16),
          Text('No CI assignments found',
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _CiCard extends StatefulWidget {
  final dynamic ci;
  final VoidCallback onTap;
  const _CiCard({required this.ci, required this.onTap});

  @override
  State<_CiCard> createState() => _CiCardState();
}

class _CiCardState extends State<_CiCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ci = widget.ci;
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
                  : AppColors.border,
            ),
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
                  color: AppColors.lenderPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.search_outlined,
                    color: AppColors.lenderPurple, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ci.loanNumber ?? 'CI Assignment',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 13, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          'Rider: ${ci.riderName ?? 'Unassigned'}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.calendar_today_outlined,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          ci.deadline != null
                              ? DateFormat('MMM d, y').format(ci.deadline!)
                              : '—',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              StatusBadge(status: ci.status),
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
