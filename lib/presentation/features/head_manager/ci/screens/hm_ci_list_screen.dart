// lib/presentation/features/head_manager/ci/screens/hm_ci_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
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
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: IconButton(onPressed: () => ref.read(hmCiProvider.notifier).fetch(), icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.textSecondary)),
        ),
      ],
      body: Column(
        children: [
          _buildFilterBar(state),
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
              onPageChange: (p) => ref.read(hmCiProvider.notifier).fetch(page: p),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(HmCiState state) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))]),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by loan # or lender…',
                hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _StatusPill(label: 'All', value: 'all', selected: state.statusFilter == 'all', onTap: (v) => ref.read(hmCiProvider.notifier).setStatus(v)),
                const SizedBox(width: 6),
                _StatusPill(label: 'Assigned', value: 'assigned', selected: state.statusFilter == 'assigned', onTap: (v) => ref.read(hmCiProvider.notifier).setStatus(v)),
                const SizedBox(width: 6),
                _StatusPill(label: 'In Progress', value: 'in_progress', selected: state.statusFilter == 'in_progress', onTap: (v) => ref.read(hmCiProvider.notifier).setStatus(v)),
                const SizedBox(width: 6),
                _StatusPill(label: 'Completed', value: 'completed', selected: state.statusFilter == 'completed', onTap: (v) => ref.read(hmCiProvider.notifier).setStatus(v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, HmCiState state) {
    // client-side search filter
    final q = _search.text.toLowerCase().trim();
    final items = q.isEmpty ? state.items : state.items.where((ci) => ci.loanNumber.toString().toLowerCase().contains(q) || ci.borrowerName.toString().toLowerCase().contains(q) || ci.riderName.toString().toLowerCase().contains(q)).toList();

    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.search_off_rounded, size: 36, color: AppColors.textTertiary)),
          const SizedBox(height: 14),
          const Text('No matches', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Try adjusting search or status filter', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final ci = items[i];
        return _CiCard(
          key: ValueKey(ci.id),
          ci: ci,
          onTap: () => context.go(RouteConstants.hmCiDetails.replaceFirst(':id', ci.id)),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.lenderBlue.withValues(alpha: 0.1), AppColors.deepNavy.withValues(alpha: 0.08)]), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.search_off_rounded, size: 40, color: AppColors.lenderBlue)),
          const SizedBox(height: 16),
          const Text('No CI assignments found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Assignments created from loan applications will appear here.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final ValueChanged<String> onTap;
  const _StatusPill({required this.label, required this.value, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.deepNavy : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.deepNavy : AppColors.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}

class _CiCard extends StatefulWidget {
  final dynamic ci;
  final VoidCallback onTap;
  const _CiCard({super.key, required this.ci, required this.onTap});

  @override
  State<_CiCard> createState() => _CiCardState();
}

class _CiCardState extends State<_CiCard> {
  bool _hover = false;

  Color _accentForStatus(String s) {
    switch (s.toLowerCase()) {
      case 'assigned':
        return AppColors.lenderBlue;
      case 'accepted':
        return AppColors.riderGreen;
      case 'in_progress':
        return AppColors.warning;
      case 'completed':
        return AppColors.riderGreen;
      case 'declined':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ci = widget.ci;
    final status = (ci.status?.toString() ?? '').toLowerCase();
    final accent = _accentForStatus(status);
    final isOverdue = ci.deadline != null && (ci.deadline as DateTime).isBefore(DateTime.now()) && status != 'completed';

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _hover ? accent.withValues(alpha: 0.3) : AppColors.border),
          boxShadow: _hover
              ? [BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))]
              : const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ci.loanNumber ?? 'CI Assignment', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _Meta(icon: Icons.delivery_dining_rounded, text: ci.riderName?.toString().isNotEmpty == true ? ci.riderName : 'Unassigned'),
                      _Meta(icon: Icons.person_outline_rounded, text: ci.borrowerName ?? '—'),
                      _Meta(
                        icon: Icons.event_rounded,
                        text: ci.deadline != null ? DateFormat('MMM d, y').format(ci.deadline!) : 'No deadline',
                        color: isOverdue ? AppColors.error : AppColors.textSecondary,
                      ),
                      if (isOverdue)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                          child: const Text('OVERDUE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.error, letterSpacing: 0.4)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              (ci.status ?? 'pending').toString().split('_').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '').join(' '),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'View',
              child: InkWell(
                onTap: widget.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_outlined, size: 14, color: AppColors.deepNavy),
                      SizedBox(width: 4),
                      Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.deepNavy)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _Meta({required this.icon, required this.text, this.color});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color ?? AppColors.textTertiary),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 12, color: color ?? AppColors.textSecondary)),
    ]);
  }
}
