// lib/presentation/features/head_manager/account_upgrade/screens/hm_account_upgrade_list_screen.dart — matched to Loan Records premium table
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../providers/hm_account_upgrade_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class HmAccountUpgradeListScreen extends ConsumerStatefulWidget {
  const HmAccountUpgradeListScreen({super.key});
  @override
  ConsumerState<HmAccountUpgradeListScreen> createState() => _HmAccountUpgradeListScreenState();
}

class _HmAccountUpgradeListScreenState extends ConsumerState<HmAccountUpgradeListScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final _dropdownTabs = const [
    _TabDef('all', 'All', Icons.layers_outlined),
    _TabDef('submitted', 'Submitted', Icons.hourglass_top_rounded),
  ];
  final _pillTabs = const [
    _TabDef('verified', 'Verified', Icons.verified_rounded),
    _TabDef('rejected', 'Rejected', Icons.cancel_rounded),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmAccountUpgradeProvider);
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDropdownActive ? AppColors.deepNavy : Colors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: isDropdownActive ? AppColors.deepNavy : AppColors.border, width: isDropdownActive ? 1.2 : 1),
              boxShadow: isDropdownActive ? [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2))] : null,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: dropdownValue,
                isDense: true,
                iconSize: 18,
                hint: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.filter_list_rounded, size: 12, color: isDropdownActive ? AppColors.gold : AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text('Pipeline', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDropdownActive ? Colors.white : AppColors.textSecondary)),
                ]),
                icon: Icon(Icons.arrow_drop_down_rounded, size: 16, color: isDropdownActive ? Colors.white : AppColors.textTertiary),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDropdownActive ? Colors.white : AppColors.textSecondary),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                items: _dropdownTabs.map((t) => DropdownMenuItem<String>(value: t.key, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(t.icon, size: 12, color: AppColors.textSecondary), const SizedBox(width: 4), Text(t.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary))]))).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  ref.read(hmAccountUpgradeProvider.notifier).setStatus(v);
                },
                selectedItemBuilder: (ctx) => _dropdownTabs.map((t) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(t.icon, size: 12, color: AppColors.gold), const SizedBox(width: 4), Text(t.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))])).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ..._pillTabs.map((t) {
            final isActive = t.key == active;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _PillTab(def: t, active: isActive, onTap: () => ref.read(hmAccountUpgradeProvider.notifier).setStatus(t.key)),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildToolbar(HmAccountUpgradeState state) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search account upgrades...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => ref.read(hmAccountUpgradeProvider.notifier).setSearch(v),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: state.statusFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'submitted', child: Text('Submitted')),
                DropdownMenuItem(value: 'verified', child: Text('Verified')),
                DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
              ],
              onChanged: (v) =>
                  ref.read(hmAccountUpgradeProvider.notifier).setStatus(v!),
            ),
          ],
        ),
      );

  Widget _buildPremiumTable(List<dynamic> docs) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 14, offset: Offset(0, 4))]),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(color: Color(0xFFF8F9FB), border: Border(bottom: BorderSide(color: AppColors.border))),
          child: const Row(children: [
            Expanded(flex: 3, child: _HLabel('Lender', Icons.person_outline)),
            Expanded(flex: 2, child: _HLabel('Documents', Icons.description_outlined)),
            Expanded(flex: 2, child: _HLabel('Submitted', Icons.event_outlined)),
            Expanded(flex: 2, child: _HLabel('Status', Icons.flag_outlined)),
            SizedBox(width: 260, child: _HLabel('Action', Icons.bolt_outlined)),
          ]),
        ),
        ...docs.asMap().entries.map((entry) {
          final idx = entry.key;
          final doc = entry.value;
          final isEven = idx.isEven;
          final status = (doc.status ?? 'pending').toString().toLowerCase();
          final date = DateFormat('MMM dd, yyyy').format(doc.submittedAt ?? doc.createdAt);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: isEven ? Colors.white : const Color(0xFFFDFDFD), border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(doc.lenderName ?? 'Unknown Lender', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(doc.lender?['email'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary), overflow: TextOverflow.ellipsis),
                ]),
              ),
              Expanded(flex: 2, child: Text(doc.documentCountLabel ?? 'Account Upgrade Submission', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(date, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600))),
              Expanded(flex: 2, child: _StatusInline(status: status)),
              SizedBox(
                width: 260,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _ActionButton(icon: Icons.visibility_outlined, label: 'View', color: AppColors.deepNavy, onPressed: () => context.go(RouteConstants.hmAccountUpgradeDetails.replaceFirst(':id', doc.lenderId.isEmpty ? doc.id : doc.lenderId)), primary: false),
                  if (status != 'verified') ...[
                    const SizedBox(width: 6),
                    _ActionButton(icon: Icons.verified_rounded, label: 'Verify', color: AppColors.riderGreen, onPressed: () => _verifyAll(doc, 'verified'), primary: true),
                    if (status != 'rejected') const SizedBox(width: 6),
                    if (status != 'rejected') _ActionButton(icon: Icons.cancel_rounded, label: 'Reject', color: AppColors.error, onPressed: () => _promptReject(doc), primary: false),
                  ],
                ]),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  Future<void> _verifyAll(dynamic doc, String action) async {
    final ok = await ref.read(hmAccountUpgradeProvider.notifier).verifyAll(lenderId: doc.lenderId.isEmpty ? doc.id : doc.lenderId, action: action);
    if (!mounted) return;
    context.showSnackBarAsToast(SnackBar(content: Text(ok ? (action == 'verified' ? 'Account upgrade documents verified' : 'Account upgrade documents rejected') : 'Action failed'), backgroundColor: ok ? AppColors.success : AppColors.error));
  }

  Future<void> _promptReject(dynamic doc) async {
    final lenderId = doc.lenderId.isEmpty ? doc.id : doc.lenderId;
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.cancel_rounded, color: AppColors.error)),
                const SizedBox(width: 12),
                const Expanded(child: Text('Reject Account Upgrade', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              ]),
              const SizedBox(height: 12),
              const Text('Rejecting will reject all submitted documents for this lender.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              const Text('Rejection Reason *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 8),
              TextField(controller: notesCtrl, maxLines: 3, decoration: InputDecoration(hintText: 'Enter reason for rejection…', filled: true, fillColor: AppColors.surfaceVariant, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.error)))),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(false), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: () { if (notesCtrl.text.trim().isEmpty) { context.showSnackBarAsToast(const SnackBar(content: Text('Please provide a rejection reason'), backgroundColor: AppColors.error)); return; } Navigator.of(context).pop(true); }, style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700)))),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (confirmed == true) {
      if (!mounted) return;
      final ok = await ref.read(hmAccountUpgradeProvider.notifier).verifyAll(lenderId: lenderId, action: 'rejected', rejectionNotes: notesCtrl.text.trim());
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

  Widget _buildEmpty(HmAccountUpgradeState state) {
    final isFiltered = state.statusFilter != 'all' || state.search.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltered ? Icons.search_off_rounded : Icons.verified_user_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'No matching submissions' : 'No account upgrade submissions found',
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
                ref.read(hmAccountUpgradeProvider.notifier).setSearch('');
                ref.read(hmAccountUpgradeProvider.notifier).setStatus('all');
              },
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPagination(HmAccountUpgradeState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Text('Page ${state.currentPage} of ${state.totalPages}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const Spacer(),
        _PageBtn(icon: Icons.chevron_left_rounded, enabled: state.currentPage > 1, onTap: () => ref.read(hmAccountUpgradeProvider.notifier).fetch(page: state.currentPage - 1)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.deepNavy, borderRadius: BorderRadius.circular(20)), child: Text('${state.currentPage} / ${state.totalPages}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
        const SizedBox(width: 8),
        _PageBtn(icon: Icons.chevron_right_rounded, enabled: state.currentPage < state.totalPages, onTap: () => ref.read(hmAccountUpgradeProvider.notifier).fetch(page: state.currentPage + 1)),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: active ? AppColors.deepNavy : Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: active ? AppColors.deepNavy : AppColors.border, width: active ? 1.2 : 1), boxShadow: active ? [BoxShadow(color: AppColors.deepNavy.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2))] : null),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(def.icon, size: 12, color: active ? AppColors.gold : AppColors.textTertiary), const SizedBox(width: 4), Text(def.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : AppColors.textSecondary))]),
      ),
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
      case 'verified': c = AppColors.success; label = 'Verified'; break;
      case 'rejected': c = AppColors.error; label = 'Rejected'; break;
      case 'submitted': c = AppColors.lenderBlue; label = 'Submitted'; break;
      default: c = AppColors.warning; label = s.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 6), Flexible(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c), overflow: TextOverflow.ellipsis))]);
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
