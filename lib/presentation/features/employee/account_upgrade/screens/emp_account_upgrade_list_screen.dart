// lib/presentation/features/head_manager/account_upgrade/screens/hm_account_upgrade_list_screen.dart — matched to Loan Records premium table
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/filter_pill_tab.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../providers/emp_account_upgrade_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class EmpAccountUpgradeListScreen extends ConsumerStatefulWidget {
  const EmpAccountUpgradeListScreen({super.key});
  @override
  ConsumerState<EmpAccountUpgradeListScreen> createState() => _EmpAccountUpgradeListScreenState();
}

class _EmpAccountUpgradeListScreenState extends ConsumerState<EmpAccountUpgradeListScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  DateTimeRange? _dateRange;

  final _dropdownTabs = const [
    FilterTabDef('all', 'All', Icons.layers_outlined),
    FilterTabDef('submitted', 'Submitted', Icons.hourglass_top_rounded),
  ];
  final _pillTabs = const [
    FilterTabDef('verified', 'Verified', Icons.verified_rounded),
    FilterTabDef('rejected', 'Rejected', Icons.cancel_rounded),
  ];

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    ref.read(empAccountUpgradeProvider.notifier).setDateRange(
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empAccountUpgradeProvider);
    final effectiveTab = state.statusFilter;

    return WebScaffold(
      title: 'Lender Account Upgrade',
      body: Container(
        color: const Color(0xFFF0F2F5),
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTabPills(effectiveTab),
              const SizedBox(height: 16),
              _buildToolbar(state),
              const SizedBox(height: 16),
              if (state.isLoading)
                _buildLoadingShimmer()
              else if (state.docs.isEmpty)
                _buildEmpty(state)
              else
                _Entrance(child: _buildPremiumTable(state.docs)),
              if (state.totalPages > 1) ...[
                const SizedBox(height: 16),
                _buildPagination(state),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabPills(String active) {
    final dropdownKeys = _dropdownTabs.map((e) => e.key).toSet();
    final isDropdownActive = dropdownKeys.contains(active);
    final dropdownValue = isDropdownActive ? active : null;
    return FilterTabBar(
      dropdownLabel: 'Pipeline',
      dropdownOptions: _dropdownTabs,
      dropdownValue: dropdownValue,
      onDropdownChanged: (v) => ref.read(empAccountUpgradeProvider.notifier).setStatus(v),
      pills: _pillTabs.map((t) {
        final isActive = t.key == active;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterPillTab(def: t, active: isActive, onTap: () => ref.read(empAccountUpgradeProvider.notifier).setStatus(t.key)),
        );
      }).toList(),
    );
  }

  Widget _buildToolbar(EmpAccountUpgradeState state) {
    final hasSearch = _searchCtrl.text.isNotEmpty;
    final resultsCount = state.totalCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: ResponsiveSearchToolbar(
        searchField: Row(children: [
          Icon(Icons.search_rounded, size: 18, color: hasSearch ? AppColors.deepNavy : AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => ref.read(empAccountUpgradeProvider.notifier).setSearch(v),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(hintText: 'Search', hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)),
            ),
          ),
          if (hasSearch)
            InkWell(
              onTap: () {
                _searchCtrl.clear();
                ref.read(empAccountUpgradeProvider.notifier).setSearch('');
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: AppColors.textTertiary.withValues(alpha: 0.14), shape: BoxShape.circle), child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textSecondary)),
            ),
          if (hasSearch) const SizedBox(width: 10),
          _ToolbarIcon(icon: Icons.refresh_rounded, tooltip: 'Refresh', onTap: () => ref.read(empAccountUpgradeProvider.notifier).fetch()),
        ]),
        trailing: [
          SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
          SearchResultsChip(count: resultsCount),
        ],
      ),
    );
  }

  Widget _buildPremiumTable(List<dynamic> docs) {
    return ResponsiveListCard(
      minTableWidth: 900,
      columns: const [
        ResponsiveCol('Lender', icon: Icons.person_outline, flex: 3),
        ResponsiveCol('Documents', icon: Icons.description_outlined, flex: 2),
        ResponsiveCol('Submitted', icon: Icons.event_outlined, flex: 2),
        ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 2),
      ],
      actionsCol: const ResponsiveActionsCol(width: 260),
      rows: docs.asMap().entries.map((entry) {
        final doc = entry.value;
        final status = (doc.status ?? 'pending').toString().toLowerCase();
        final date = DateFormat('MMM dd, yyyy h:mm a').format(doc.submittedAt ?? doc.createdAt);
        return ResponsiveRow(
          cells: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(doc.lenderName ?? 'Unknown Lender', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(doc.lender?['email'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary), overflow: TextOverflow.ellipsis),
            ]),
            Text(doc.documentCountLabel ?? 'Account Upgrade Submission', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
            Text(date, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            _StatusInline(status: status),
          ],
          actions: Row(mainAxisSize: MainAxisSize.min, children: [
            _ActionButton(icon: Icons.visibility_outlined, label: 'View', color: AppColors.deepNavy, onPressed: () => context.go(RouteConstants.empAccountUpgradeDetails.replaceFirst(':id', doc.lenderId.isEmpty ? doc.id : doc.lenderId)), primary: false),
            // Only actionable statuses show Verify/Reject.
            // Verified and rejected submissions show View only —
            // Verify must not appear once rejected.
            if (status == 'submitted' || status == 'pending' || status == 'under_review') ...[
              const SizedBox(width: 6),
              _ActionButton(icon: Icons.verified_rounded, label: 'Verify', color: AppColors.riderGreen, onPressed: () => _verifyAll(doc, 'verified'), primary: true),
              const SizedBox(width: 6),
              _ActionButton(icon: Icons.cancel_rounded, label: 'Reject', color: AppColors.error, onPressed: () => _promptReject(doc), primary: false),
            ],
          ]),
        );
      }).toList(),
    );
  }

  Future<void> _verifyAll(dynamic doc, String action) async {
    final ok = await ref.read(empAccountUpgradeProvider.notifier).verifyAll(lenderId: doc.lenderId.isEmpty ? doc.id : doc.lenderId, action: action);
    if (!mounted) return;
    context.showSnackBarAsToast(SnackBar(content: Text(ok ? (action == 'verified' ? 'Account upgrade documents verified' : 'Account upgrade documents rejected') : 'Action failed'), backgroundColor: ok ? AppColors.success : AppColors.error));
  }

  Future<void> _promptReject(dynamic doc) async {
    final lenderId = doc.lenderId.isEmpty ? doc.id : doc.lenderId;
    // No reason required — simple Yes / No confirm.
    // Yes => reject, No => cancel (do not reject).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.cancel_rounded, color: AppColors.error)),
                const SizedBox(width: 12),
                const Expanded(child: Text('Reject Account Upgrade?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              ]),
              const SizedBox(height: 12),
              const Text('Do you want to reject this lender\'s account upgrade submission?', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(false), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('No'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Yes', style: TextStyle(fontWeight: FontWeight.w700)))),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (confirmed == true) {
      if (!mounted) return;
      final ok = await ref.read(empAccountUpgradeProvider.notifier).verifyAll(lenderId: lenderId, action: 'rejected');
      if (!mounted) return;
      context.showSnackBarAsToast(SnackBar(content: Text(ok ? 'Account upgrade documents rejected' : 'Action failed'), backgroundColor: ok ? AppColors.success : AppColors.error));
    }
  }

  Widget _buildLoadingShimmer() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.all(16),
      child: Column(children: List.generate(6, (i) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.shimmerBase.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 12, decoration: BoxDecoration(color: AppColors.shimmerBase.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6))), const SizedBox(height: 8), Container(height: 10, width: 160, decoration: BoxDecoration(color: AppColors.shimmerHighlight.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6)))] )), const SizedBox(width: 16), Container(width: 86, height: 28, decoration: BoxDecoration(color: AppColors.shimmerBase.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(20)))])))),
    );
  }

  Widget _buildEmpty(EmpAccountUpgradeState state) {
    final isFiltered = state.statusFilter != 'all' || state.search.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))]),
      child: Column(children: [
        Container(width: 72, height: 72, decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFF00838F).withValues(alpha: 0.12), AppColors.deepNavy.withValues(alpha: 0.08)]), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.verified_user_rounded, size: 40, color: Color(0xFF00838F))),
        const SizedBox(height: 16),
        Text(isFiltered ? 'No matching submissions' : 'No account upgrade submissions found', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(isFiltered ? 'Try a different filter.' : 'Lender KYC upgrade requests will appear here for review.', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
        if (isFiltered) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(onPressed: () { _searchCtrl.clear(); ref.read(empAccountUpgradeProvider.notifier).setSearch(''); ref.read(empAccountUpgradeProvider.notifier).setStatus('all'); }, icon: const Icon(Icons.clear_all_rounded, size: 16), label: const Text('Clear filters')),
        ],
      ]),
    );
  }

  Widget _buildPagination(EmpAccountUpgradeState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(children: [
        Text('Page ${state.currentPage} of ${state.totalPages}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const Spacer(),
        _PageBtn(icon: Icons.chevron_left_rounded, enabled: state.currentPage > 1, onTap: () => ref.read(empAccountUpgradeProvider.notifier).fetch(page: state.currentPage - 1)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(20)), child: Text('${state.currentPage} / ${state.totalPages}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
        const SizedBox(width: 8),
        _PageBtn(icon: Icons.chevron_right_rounded, enabled: state.currentPage < state.totalPages, onTap: () => ref.read(empAccountUpgradeProvider.notifier).fetch(page: state.currentPage + 1)),
      ]),
    );
  }
}




class _StatusInline extends StatelessWidget {
  final String status;
  const _StatusInline({required this.status});
  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final Color c;
    final String label;
    switch (s) {
      case 'verified': c = AppColors.success; label = 'Verified'; break;
      case 'rejected': c = AppColors.error; label = 'Rejected'; break;
      case 'submitted': c = AppColors.lenderBlue; label = 'Submitted'; break;
      default: c = AppColors.warning; label = s.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 6), Flexible(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c), overflow: TextOverflow.ellipsis))]);
  }
}

class _ToolbarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ToolbarIcon({required this.icon, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Tooltip(message: tooltip, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(9), child: Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9), border: Border.all(color: AppColors.border)), child: Icon(icon, size: 16, color: AppColors.textSecondary))));
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
      child: Container(width: 32, height: 32, decoration: BoxDecoration(color: enabled ? Colors.white : AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)), child: Icon(icon, size: 18, color: enabled ? AppColors.textPrimary : AppColors.textTertiary)),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool primary;
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onPressed, required this.primary});
  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: BorderRadius.zero,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.primary ? (_hover ? widget.color : widget.color.withValues(alpha: 0.1)) : (_hover ? widget.color.withValues(alpha: 0.12) : Colors.white),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: widget.color.withValues(alpha: widget.primary ? 0.2 : 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 14, color: widget.primary ? (_hover ? Colors.white : widget.color) : widget.color),
            const SizedBox(width: 6),
            Text(widget.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: widget.primary ? (_hover ? Colors.white : widget.color) : widget.color)),
          ]),
        ),
      ),
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
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _opacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: widget.child);
}
