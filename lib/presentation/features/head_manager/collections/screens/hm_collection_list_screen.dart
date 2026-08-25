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
import '../../../../shared/widgets/tables/table_pagination.dart';
import '../providers/hm_collection_provider.dart';
import '../widgets/assign_rider_collection_modal.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class HmCollectionListScreen extends ConsumerStatefulWidget {
  const HmCollectionListScreen({super.key});

  @override
  ConsumerState<HmCollectionListScreen> createState() => _HmCollectionListScreenState();
}

class _HmCollectionListScreenState extends ConsumerState<HmCollectionListScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmCollectionProvider);

    return WebScaffold(
      title: 'Collections',
      actions: [
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: IconButton(onPressed: () => ref.read(hmCollectionProvider.notifier).fetch(), icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.textSecondary)),
        ),
      ],
      body: Column(
        children: [
          _buildFilterBar(state),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.items.isEmpty
                    ? (state.error != null ? _buildError(context, ref, state.error!) : _buildEmpty())
                    : _buildList(context, state),
          ),
          if (state.totalPages > 1)
            TablePagination(currentPage: state.currentPage, totalPages: state.totalPages, totalCount: state.totalCount, onPageChange: (p) => ref.read(hmCollectionProvider.notifier).fetch(page: p)),
        ],
      ),
    );
  }

  Widget _buildFilterBar(HmCollectionState state) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))]),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by loan # or lender…',
                hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _StatusPill(label: 'All', value: 'all', selected: state.statusFilter == 'all', onTap: (v) => ref.read(hmCollectionProvider.notifier).setStatus(v)),
              const SizedBox(width: 6),
              _StatusPill(label: 'Requested', value: 'requested', selected: state.statusFilter == 'requested', onTap: (v) => ref.read(hmCollectionProvider.notifier).setStatus(v)),
              const SizedBox(width: 6),
              _StatusPill(label: 'Assigned', value: 'assigned', selected: state.statusFilter == 'assigned', onTap: (v) => ref.read(hmCollectionProvider.notifier).setStatus(v)),
              const SizedBox(width: 6),
              _StatusPill(label: 'In Progress', value: 'in_progress', selected: state.statusFilter == 'in_progress', onTap: (v) => ref.read(hmCollectionProvider.notifier).setStatus(v)),
              const SizedBox(width: 6),
              _StatusPill(label: 'Completed', value: 'completed', selected: state.statusFilter == 'completed', onTap: (v) => ref.read(hmCollectionProvider.notifier).setStatus(v)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, HmCollectionState state) {
    final q = _search.text.toLowerCase().trim();
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final items = q.isEmpty ? state.items : state.items.where((c) => c.loanNumber.toString().toLowerCase().contains(q) || c.lenderName.toString().toLowerCase().contains(q) || c.riderName.toString().toLowerCase().contains(q)).toList();
    if (items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.search_off_rounded, size: 36, color: AppColors.textTertiary)),
        const SizedBox(height: 14),
        const Text('No matches', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Try a different search or status filter', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ]));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _CollectionCard(key: ValueKey(items[i].id), collection: items[i], fmt: fmt, onTap: () => context.go(RouteConstants.hmCollectionDetails.replaceFirst(':id', items[i].id))),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
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

  Widget _buildEmpty() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.riderGreen.withValues(alpha: 0.12), AppColors.deepNavy.withValues(alpha: 0.08)]), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.delivery_dining_rounded, size: 40, color: AppColors.riderGreen)),
          const SizedBox(height: 16),
          const Text('No collections found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Rider collection assignments will appear here once requested.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
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
        decoration: BoxDecoration(color: selected ? AppColors.deepNavy : AppColors.surfaceVariant, borderRadius: BorderRadius.circular(20), border: Border.all(color: selected ? AppColors.deepNavy : AppColors.border)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}

class _CollectionCard extends ConsumerStatefulWidget {
  final dynamic collection;
  final NumberFormat fmt;
  final VoidCallback onTap;
  const _CollectionCard({super.key, required this.collection, required this.fmt, required this.onTap});

  @override
  ConsumerState<_CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends ConsumerState<_CollectionCard> {
  bool _hover = false;

  bool get _canAssign {
    final col = widget.collection;
    final isOffice = col.collectionType == 'office';
    return col.status == 'requested' && !isOffice;
  }

  Future<void> _assignRider() async {
    final col = widget.collection;
    final loanScheduleId = col.loanScheduleId as String? ?? '';
    final loanId = (col.loanSchedule?['loan']?['id'] as String?) ?? (col.loanSchedule?['loan_id'] as String?) ?? '';
    final result = await showDialog<bool>(context: context, builder: (_) => AssignRiderCollectionModal(loanScheduleId: loanScheduleId, loanId: loanId, assignmentId: col.id as String? ?? ''));
    if (result == true && mounted) context.showSnackBarAsToast(const SnackBar(content: Text('Rider assigned successfully'), backgroundColor: AppColors.success));
  }

  Color _accentForStatus(String s) {
    switch (s.toLowerCase()) {
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

  @override
  Widget build(BuildContext context) {
    final col = widget.collection;
    final schedule = col.loanSchedule as Map<String, dynamic>? ?? {};
    final isOffice = col.collectionType == 'office';
    final amount = col.amountCollected ?? (schedule['amount_due'] as num?)?.toDouble() ?? 0.0;
    final status = (col.status?.toString() ?? '').toLowerCase();
    final accent = _accentForStatus(status);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hover ? accent.withValues(alpha: 0.3) : AppColors.border),
            boxShadow: _hover ? [BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))] : const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Row(
            children: [
              Container(width: 4, height: 56, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(col.lenderName.isNotEmpty ? col.lenderName : 'Unknown lender', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
                    if (isOffice)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFF00838F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: const Text('OFFICE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF00838F), letterSpacing: 0.6)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(col.loanNumber.isNotEmpty ? col.loanNumber : '—', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [Icon(isOffice ? Icons.storefront_rounded : Icons.delivery_dining_rounded, size: 13, color: AppColors.textTertiary), const SizedBox(width: 4), Flexible(child: Text(isOffice ? 'Office visit payment' : col.riderName.isNotEmpty ? col.riderName : 'Unassigned', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis))]),
                    if (col.collectionSchedule != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.event_rounded, size: 12, color: AppColors.textTertiary), const SizedBox(width: 4), Text(DateFormat('MMM d, y').format(col.collectionSchedule!), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))]),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₱${widget.fmt.format(amount)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: amount > 0 ? AppColors.deepNavy : AppColors.textSecondary)),
                const SizedBox(height: 4),
                StatusBadge(status: col.status),
              ]),
              const SizedBox(width: 10),
              if (_canAssign)
                InkWell(
                  onTap: () => _assignRider(),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.riderGreen, AppColors.riderGreenDark]), borderRadius: BorderRadius.circular(9), boxShadow: [BoxShadow(color: AppColors.riderGreen.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))]),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.delivery_dining_rounded, size: 14, color: Colors.white), SizedBox(width: 6), Text('Assign', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))]),
                  ),
                ),
              if (_canAssign) const SizedBox(width: 8),
              Tooltip(
                message: 'View',
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.deepNavy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.deepNavy.withValues(alpha: 0.14)),
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
