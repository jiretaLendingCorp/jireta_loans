// lib/presentation/features/employee/ci/screens/emp_ci_list_screen.dart — matched to Loan Records premium table design
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../providers/emp_ci_provider.dart';

class EmpCiListScreen extends ConsumerStatefulWidget {
  const EmpCiListScreen({super.key});
  @override
  ConsumerState<EmpCiListScreen> createState() => _EmpCiListScreenState();
}

class _EmpCiListScreenState extends ConsumerState<EmpCiListScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final _dropdownTabs = const [
    _TabDef('all', 'All', Icons.layers_outlined),
    _TabDef('assigned', 'Assigned', Icons.assignment_ind_outlined),
    _TabDef('in_progress', 'In Progress', Icons.timelapse_rounded),
    _TabDef('completed', 'Pending Approval', Icons.verified_outlined),
  ];
  final _pillTabs = const [
    _TabDef('approved', 'Approved', Icons.check_circle_outline),
    _TabDef('rejected', 'Rejected', Icons.cancel_outlined),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empCiProvider);
    return WebScaffold(
      title: 'Credit Investigations',
      body: Container(
        color: const Color(0xFFF0F2F5),
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildTabPills(state.statusFilter),
            const SizedBox(height: 16),
            _buildToolbar(state),
            const SizedBox(height: 16),
            if (state.isLoading)
              _buildLoadingShimmer()
            else if (state.items.isEmpty)
              _buildEmpty(state)
            else
              _Entrance(child: _buildPremiumTable(_filtered(state.items))),
            if (state.totalPages > 1) ...[
              const SizedBox(height: 16),
              _buildPagination(state),
            ],
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  List<dynamic> _filtered(List<dynamic> items) {
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return items;
    return items.where((ci) => ci.loanNumber.toString().toLowerCase().contains(q) || ci.borrowerName.toString().toLowerCase().contains(q) || ci.riderName.toString().toLowerCase().contains(q)).toList();
  }

  Widget _buildTabPills(String active) {
    final dropdownKeys = _dropdownTabs.map((e) => e.key).toSet();
    final isDropdownActive = dropdownKeys.contains(active);
    final dropdownValue = isDropdownActive ? active : null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: isDropdownActive ? AppColors.deepNavy : Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: isDropdownActive ? AppColors.deepNavy : AppColors.border, width: isDropdownActive ? 1.2 : 1), boxShadow: isDropdownActive ? [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2))] : null),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: dropdownValue,
              isDense: true,
              iconSize: 18,
              hint: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.filter_list_rounded, size: 12, color: isDropdownActive ? AppColors.gold : AppColors.textTertiary), const SizedBox(width: 4), Text('Pipeline', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDropdownActive ? Colors.white : AppColors.textSecondary))]),
              icon: Icon(Icons.arrow_drop_down_rounded, size: 16, color: isDropdownActive ? Colors.white : AppColors.textTertiary),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDropdownActive ? Colors.white : AppColors.textSecondary),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              items: _dropdownTabs.map((t) => DropdownMenuItem<String>(value: t.key, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(t.icon, size: 12, color: AppColors.textSecondary), const SizedBox(width: 4), Text(t.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary))]))).toList(),
              onChanged: (v) {
                if (v == null) return;
                ref.read(empCiProvider.notifier).setStatus(v);
              },
              selectedItemBuilder: (ctx) => _dropdownTabs.map((t) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(t.icon, size: 12, color: AppColors.gold), const SizedBox(width: 4), Text(t.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))])).toList(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ..._pillTabs.map((t) {
          final isActive = t.key == active;
          return Padding(padding: const EdgeInsets.only(right: 8), child: _PillTab(def: t, active: isActive, onTap: () => ref.read(empCiProvider.notifier).setStatus(t.key)));
        }),
      ]),
    );
  }

  Widget _buildToolbar(EmpCiState state) {
    final hasSearch = _searchCtrl.text.isNotEmpty;
    final resultsCount = _filtered(state.items).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 2))]),
      child: Row(children: [
        Icon(Icons.search_rounded, size: 18, color: hasSearch ? AppColors.deepNavy : AppColors.textTertiary),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _searchCtrl, onChanged: (v) => setState(() {}), style: const TextStyle(fontSize: 13), decoration: const InputDecoration(hintText: 'Search', hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)))),
        if (hasSearch) InkWell(onTap: () => setState(() => _searchCtrl.clear()), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: AppColors.textTertiary.withValues(alpha: 0.14), shape: BoxShape.circle), child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textSecondary))),
        if (hasSearch) const SizedBox(width: 10),
        _ToolbarIcon(icon: Icons.refresh_rounded, tooltip: 'Refresh', onTap: () => ref.read(empCiProvider.notifier).fetch()),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.layers_outlined, size: 14, color: Colors.white), const SizedBox(width: 6), Text('$resultsCount results', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))])),
      ]),
    );
  }

  Widget _buildPremiumTable(List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 14, offset: Offset(0, 4))]),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(color: Color(0xFFF8F9FB), border: Border(bottom: BorderSide(color: AppColors.border))),
          child: const Row(children: [
            Expanded(flex: 3, child: _HLabel('Lender & Loan', Icons.person_outline)),
            Expanded(flex: 2, child: _HLabel('Rider', Icons.delivery_dining_outlined)),
            Expanded(flex: 2, child: _HLabel('Deadline', Icons.event_outlined)),
            Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: _HLabel('Status', Icons.flag_outlined))),
            Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: _HLabel('Action', Icons.bolt_outlined))),
          ]),
        ),
        ...items.asMap().entries.map((entry) {
          final idx = entry.key;
          final ci = entry.value;
          final isEven = idx.isEven;
          final status = (ci.status ?? 'pending').toString().toLowerCase();
          final isPendingApproval = status == 'completed';
          final isOverdue = ci.deadline != null && (ci.deadline as DateTime).isBefore(DateTime.now()) && status != 'completed';
          return Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: isEven ? Colors.white : const Color(0xFFFDFDFD), border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ci.loanNumber ?? 'CI Assignment', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(ci.borrowerName ?? '—', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary), overflow: TextOverflow.ellipsis),
                  ]),
                ),
                Expanded(flex: 2, child: Text(ci.riderName?.toString().isNotEmpty == true ? ci.riderName : 'Unassigned', style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                Expanded(
                  flex: 2,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ci.deadline != null ? DateFormat('MMM dd, yyyy').format(ci.deadline!) : '—', style: TextStyle(fontSize: 13, color: isOverdue ? AppColors.error : AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    if (isOverdue) Container(margin: const EdgeInsets.only(top: 2), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: const Text('OVERDUE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.error, letterSpacing: 0.4))),
                  ]),
                ),
                Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: _StatusInline(status: status))),
                Expanded(flex: 2, child: _EmpActionCell(ci: ci, isPending: isPendingApproval)),
              ]),
            ),
          ]);
        }),
      ]),
    );
  }

  Widget _buildLoadingShimmer() {
    return Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)), padding: const EdgeInsets.all(16), child: Column(children: List.generate(6, (i) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.shimmerBase.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 12, decoration: BoxDecoration(color: AppColors.shimmerBase.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6))), const SizedBox(height: 8), Container(height: 10, width: 160, decoration: BoxDecoration(color: AppColors.shimmerHighlight.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6)))] )), const SizedBox(width: 16), Container(width: 86, height: 28, decoration: BoxDecoration(color: AppColors.shimmerBase.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(20)))])))));
  }

  Widget _buildEmpty(EmpCiState state) {
    final isFiltered = _searchCtrl.text.isNotEmpty || state.statusFilter != 'all';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))]),
      child: Column(children: [
        Container(width: 72, height: 72, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.deepNavy.withValues(alpha: 0.10), AppColors.gold.withValues(alpha: 0.16)], begin: Alignment.topLeft, end: Alignment.bottomRight), shape: BoxShape.circle, border: Border.all(color: AppColors.border)), child: Icon(isFiltered ? Icons.search_off_rounded : Icons.search_outlined, size: 32, color: AppColors.deepNavy.withValues(alpha: 0.75))),
        const SizedBox(height: 16),
        Text(isFiltered ? 'No matching investigations' : 'No CI assignments found', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(isFiltered ? 'Try adjusting your search or switch to a different status.' : 'Assignments created from loan applications will appear here.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        if (isFiltered) ...[
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton.icon(onPressed: () { _searchCtrl.clear(); ref.read(empCiProvider.notifier).setStatus('all'); setState(() {}); }, icon: const Icon(Icons.clear_all_rounded, size: 16), label: const Text('Clear filters')),
            const SizedBox(width: 10),
            ElevatedButton.icon(onPressed: () => ref.read(empCiProvider.notifier).fetch(), icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.deepNavy, foregroundColor: Colors.white)),
          ]),
        ],
      ]),
    );
  }

  Widget _buildPagination(EmpCiState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Text('Page ${state.currentPage} of ${state.totalPages}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const Spacer(),
        _PageBtn(icon: Icons.chevron_left_rounded, enabled: state.currentPage > 1, onTap: () => ref.read(empCiProvider.notifier).fetch(page: state.currentPage - 1)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(20)), child: Text('${state.currentPage} / ${state.totalPages}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
        const SizedBox(width: 8),
        _PageBtn(icon: Icons.chevron_right_rounded, enabled: state.currentPage < state.totalPages, onTap: () => ref.read(empCiProvider.notifier).fetch(page: state.currentPage + 1)),
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
      child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: active ? AppColors.deepNavy : Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: active ? AppColors.deepNavy : AppColors.border, width: active ? 1.2 : 1), boxShadow: active ? [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2))] : null), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(def.icon, size: 12, color: active ? AppColors.gold : AppColors.textTertiary), const SizedBox(width: 4), Text(def.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : AppColors.textSecondary))])),
    );
  }
}

class _HLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  const _HLabel(this.text, this.icon);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: AppColors.textTertiary), const SizedBox(width: 6), Flexible(child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5), overflow: TextOverflow.ellipsis))]);
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
      case 'assigned': c = AppColors.lenderBlue; label = 'Assigned'; break;
      case 'in_progress': c = AppColors.warning; label = 'In Progress'; break;
      case 'completed': c = AppColors.warning; label = 'Pending Approval'; break;
      case 'approved': c = AppColors.success; label = 'Approved'; break;
      case 'rejected': c = AppColors.error; label = 'Rejected'; break;
      case 'declined': c = AppColors.error; label = 'Declined'; break;
      default: c = AppColors.textSecondary; label = s.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
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
    return InkWell(onTap: enabled ? onTap : null, borderRadius: BorderRadius.circular(8), child: Container(width: 32, height: 32, decoration: BoxDecoration(color: enabled ? Colors.white : AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)), child: Icon(icon, size: 18, color: enabled ? AppColors.textPrimary : AppColors.textTertiary)));
  }
}

class _TableApproveButton extends ConsumerStatefulWidget {
  final dynamic ci;
  final bool isHm;
  final String label;
  final IconData icon;
  final Color color;
  const _TableApproveButton({required this.ci, required this.isHm, required this.label, required this.icon, required this.color});
  @override
  ConsumerState<_TableApproveButton> createState() => _TableApproveButtonState();
}

class _TableApproveButtonState extends ConsumerState<_TableApproveButton> {
  bool _loading = false;
  Future<void> _onTap() async {
    if (widget.label == 'Approve') {
      setState(() => _loading = true);
      final ok = await ref.read(empCiProvider.notifier).approveReport(ciId: widget.ci.id as String);
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'CI approved — loan ready for final approval' : 'Approve failed: ${ref.read(empCiProvider).error ?? 'error'}'), backgroundColor: ok ? AppColors.success : AppColors.error));
    } else {
      final reasonCtrl = TextEditingController();
      final reason = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Reject CI Report'), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Provide reason (min 10 chars).', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)), const SizedBox(height: 12), TextField(controller: reasonCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Rejection reason', border: OutlineInputBorder()))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () { final r = reasonCtrl.text.trim(); if (r.length < 10) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reason must be at least 10 characters'))); return; } Navigator.pop(context, r); }, style: ElevatedButton.styleFrom(backgroundColor: AppColors.error), child: const Text('Reject', style: TextStyle(color: Colors.white)))]));
      if (reason == null) return;
      setState(() => _loading = true);
      final ok = await ref.read(empCiProvider.notifier).rejectReport(ciId: widget.ci.id as String, reason: reason);
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'CI rejected — loan returned to review' : 'Reject failed: ${ref.read(empCiProvider).error ?? 'error'}'), backgroundColor: ok ? AppColors.error : AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _loading ? null : _onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: widget.color,
        side: const BorderSide(color: AppColors.border),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: _loading
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: widget.color))
          : Text(widget.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: widget.color)),
    );
  }
}


class _EmpActionCell extends ConsumerWidget {
  final dynamic ci;
  final bool isPending;
  const _EmpActionCell({required this.ci, required this.isPending});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isPending) {
      return Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => context.go(RouteConstants.empCiDetails.replaceFirst(':id', ci.id)),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.visibility_outlined, size: 14, color: AppColors.deepNavy), SizedBox(width: 4), Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.deepNavy))]),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _TableApproveButton(ci: ci, isHm: false, label: 'Reject', icon: Icons.close_rounded, color: AppColors.error),
        _TableApproveButton(ci: ci, isHm: false, label: 'Approve', icon: Icons.check_rounded, color: AppColors.success),
        PopupMenuButton<String>(
          tooltip: 'Actions',
          offset: const Offset(0, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility_outlined, size: 16, color: AppColors.deepNavy), SizedBox(width: 8), Text('View')])),
          ],
          onSelected: (v) {
            if (v == 'view') context.go(RouteConstants.empCiDetails.replaceFirst(':id', ci.id));
          },
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: const Icon(Icons.more_horiz_rounded, size: 16, color: AppColors.textSecondary),
          ),
        ),
      ],
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
