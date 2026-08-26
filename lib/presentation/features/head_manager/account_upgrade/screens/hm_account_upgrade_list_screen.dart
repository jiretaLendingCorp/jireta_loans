// lib/presentation/features/head_manager/account_upgrade/screens/hm_account_upgrade_list_screen.dart
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
import '../providers/hm_account_upgrade_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class HmAccountUpgradeListScreen extends ConsumerStatefulWidget {
  const HmAccountUpgradeListScreen({super.key});

  @override
  ConsumerState<HmAccountUpgradeListScreen> createState() =>
      _HmAccountUpgradeListScreenState();
}

class _HmAccountUpgradeListScreenState
    extends ConsumerState<HmAccountUpgradeListScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmAccountUpgradeProvider);

    return WebScaffold(
      title: 'Lender Account Upgrade',
      actions: [
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: IconButton(onPressed: () => ref.read(hmAccountUpgradeProvider.notifier).fetch(), icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.textSecondary), tooltip: 'Refresh'),
        ),
      ],
      body: Column(
        children: [
          _buildFilterBar(state),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.docs.isEmpty
                    ? _buildEmpty()
                    : _buildList(context, state),
          ),
          if (state.totalPages > 1)
            TablePagination(
              currentPage: state.currentPage,
              totalPages: state.totalPages,
              totalCount: state.totalCount,
              onPageChange: (p) =>
                  ref.read(hmAccountUpgradeProvider.notifier).fetch(page: p),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(HmAccountUpgradeState state) {
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
                hintText: 'Search lender name…',
                hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _StatusPill(label: 'All', value: 'all', selected: state.statusFilter == 'all', onTap: (v) => ref.read(hmAccountUpgradeProvider.notifier).setStatus(v)),
              const SizedBox(width: 6),
              _StatusPill(label: 'Submitted', value: 'submitted', selected: state.statusFilter == 'submitted', onTap: (v) => ref.read(hmAccountUpgradeProvider.notifier).setStatus(v)),
              const SizedBox(width: 6),
              _StatusPill(label: 'Verified', value: 'verified', selected: state.statusFilter == 'verified', onTap: (v) => ref.read(hmAccountUpgradeProvider.notifier).setStatus(v)),
              const SizedBox(width: 6),
              _StatusPill(label: 'Rejected', value: 'rejected', selected: state.statusFilter == 'rejected', onTap: (v) => ref.read(hmAccountUpgradeProvider.notifier).setStatus(v)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, HmAccountUpgradeState state) {
    final q = _search.text.toLowerCase().trim();
    final docs = q.isEmpty ? state.docs : state.docs.where((d) => d.lenderName.toString().toLowerCase().contains(q) || (d.lender?['email']?.toString().toLowerCase().contains(q) ?? false)).toList();
    if (docs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.search_off_rounded, size: 36, color: AppColors.textTertiary)),
          const SizedBox(height: 14),
          const Text('No matches', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Try a different search or filter', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final doc = docs[i];
        return Padding(
          padding: EdgeInsets.only(bottom: i == docs.length - 1 ? 0 : 10),
          child: _AccountUpgradeRow(
            key: ValueKey(doc.id),
            doc: doc,
            onTap: () => context.go(RouteConstants.hmAccountUpgradeDetails.replaceFirst(':id', doc.lenderId.isEmpty ? doc.id : doc.lenderId)),
            onVerify: () => _verifyAll(doc, 'verified'),
            onReject: () => _promptReject(doc),
          ),
        );
      },
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

  Widget _buildEmpty() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFF00838F).withValues(alpha: 0.12), AppColors.deepNavy.withValues(alpha: 0.08)]), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.verified_user_rounded, size: 40, color: Color(0xFF00838F))),
          const SizedBox(height: 16),
          const Text('No account upgrade submissions found', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Lender KYC upgrade requests will appear here for review.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
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

class _AccountUpgradeRow extends StatefulWidget {
  final dynamic doc;
  final VoidCallback onTap;
  final VoidCallback onVerify;
  final VoidCallback onReject;

  const _AccountUpgradeRow({super.key, required this.doc, required this.onTap, required this.onVerify, required this.onReject});

  @override
  State<_AccountUpgradeRow> createState() => _AccountUpgradeRowState();
}

class _AccountUpgradeRowState extends State<_AccountUpgradeRow> {
  bool _hovered = false;

  Color _accentForStatus(String s) {
    switch (s.toLowerCase()) {
      case 'verified':
        return AppColors.riderGreen;
      case 'rejected':
        return AppColors.error;
      case 'submitted':
        return AppColors.lenderBlue;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final date = DateFormat('MMM d, y').format(doc.submittedAt ?? doc.createdAt);
    final status = (doc.status ?? 'pending').toString();
    final accent = _accentForStatus(status);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _hovered ? accent.withValues(alpha: 0.3) : AppColors.border),
          boxShadow: _hovered ? [BoxShadow(color: accent.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 6))] : const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(width: 4, height: 48, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(doc.lenderName ?? 'Unknown Lender', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
                  StatusBadge(status: status),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)), child: Text(doc.documentCountLabel ?? 'Account Upgrade Submission', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent))),
                  const SizedBox(width: 8),
                  const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text(date, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
            // Desktop actions
            if (MediaQuery.of(context).size.width >= 640) ...[
              if (status != 'verified')
                _ActionButton(icon: Icons.verified_rounded, label: 'Verify', color: AppColors.riderGreen, onPressed: widget.onVerify, primary: true),
              if (status != 'verified' && status != 'rejected') const SizedBox(width: 8),
              if (status != 'verified' && status != 'rejected')
                _ActionButton(icon: Icons.cancel_rounded, label: 'Reject', color: AppColors.error, onPressed: widget.onReject, primary: false),
              const SizedBox(width: 10),
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
            ] else ...[
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
          ],
        ),
      ),
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
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.primary ? (_hover ? widget.color : widget.color.withValues(alpha: 0.1)) : (_hover ? widget.color.withValues(alpha: 0.12) : Colors.white),
            borderRadius: BorderRadius.circular(9),
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
