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
import '../../../../shared/widgets/profile_avatar.dart';
import '../../../../shared/widgets/tables/table_filter_bar.dart';
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
      title: 'Account Upgrade Review',
      actions: [
        IconButton(
          onPressed: () => ref.read(hmAccountUpgradeProvider.notifier).fetch(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          tooltip: 'Refresh',
        ),
      ],
      body: Column(
        children: [
          buildFilterBar(
            searchController: _search,
            searchHint: 'Search lender name...',
            filters: [
              (
                label: 'Status',
                value: state.statusFilter,
                options: ['all', 'submitted', 'verified', 'rejected'],
                onChanged: (v) =>
                    ref.read(hmAccountUpgradeProvider.notifier).setStatus(v),
              ),
            ],
            onExport: null,
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : state.docs.isEmpty
                    ? _buildEmpty()
                    : _buildTable(context, state),
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

  Widget _buildTable(BuildContext context, HmAccountUpgradeState state) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: state.docs.map((doc) {
            return _AccountUpgradeRow(
              key: ValueKey(doc.id),
              doc: doc,
              onTap: () => context.go(
                RouteConstants.hmAccountUpgradeDetails.replaceFirst(
                    ':id', doc.lenderId.isEmpty ? doc.id : doc.lenderId),
              ),
              onVerify: () => _verifyAll(doc, 'verified'),
              onReject: () => _promptReject(doc),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _verifyAll(dynamic doc, String action) async {
    final ok = await ref.read(hmAccountUpgradeProvider.notifier).verifyAll(
          lenderId: doc.lenderId.isEmpty ? doc.id : doc.lenderId,
          action: action,
        );
    if (!mounted) return;
    context.showSnackBarAsToast(
      SnackBar(
        content: Text(ok
            ? (action == 'verified'
                ? 'Account upgrade documents verified'
                : 'Account upgrade documents rejected')
            : 'Action failed'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _promptReject(dynamic doc) async {
    final lenderId = doc.lenderId.isEmpty ? doc.id : doc.lenderId;
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.error, size: 24),
            SizedBox(width: 10),
            Text('Reject Account Upgrade'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rejecting will reject all submitted documents for this lender.',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              const Text('Rejection Reason *',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter reason for rejection...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (notesCtrl.text.trim().isEmpty) {
                context.showSnackBarAsToast(
                  const SnackBar(
                    content: Text('Please provide a rejection reason'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(true);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (!mounted) return;
      final ok = await ref.read(hmAccountUpgradeProvider.notifier).verifyAll(
            lenderId: lenderId,
            action: 'rejected',
            rejectionNotes: notesCtrl.text.trim(),
          );
      if (!mounted) return;
      context.showSnackBarAsToast(
        SnackBar(
          content:
              Text(ok ? 'Account upgrade documents rejected' : 'Action failed'),
          backgroundColor: ok ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_outlined,
              size: 64, color: AppColors.textTertiary),
          SizedBox(height: 16),
          Text(
            'No account upgrade submissions found',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _AccountUpgradeRow extends StatefulWidget {
  final dynamic doc;
  final VoidCallback onTap;
  final VoidCallback onVerify;
  final VoidCallback onReject;

  const _AccountUpgradeRow({
    super.key,
    required this.doc,
    required this.onTap,
    required this.onVerify,
    required this.onReject,
  });

  @override
  State<_AccountUpgradeRow> createState() => _AccountUpgradeRowState();
}

class _AccountUpgradeRowState extends State<_AccountUpgradeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final date =
        DateFormat('MMM d, y').format(doc.submittedAt ?? doc.createdAt);
    final status = (doc.status ?? 'pending').toString();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.deepNavy.withValues(alpha: 0.03)
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? AppColors.deepNavy.withValues(alpha: 0.2)
                  : AppColors.border,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppColors.deepNavy.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [
                    const BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    )
                  ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 620;
              final avatar = ProfileAvatar(
                photoUrl: doc.lender?['profile_photo_url'] as String?,
                name: doc.lenderName,
                color: AppColors.info,
                radius: 20,
                fallback: const Icon(Icons.verified_user_outlined,
                    size: 20, color: AppColors.info),
              );
              final info = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.lenderName ?? 'Unknown Lender',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${doc.documentCountLabel ?? 'Account Upgrade Submission'}  •  $date',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              );
              final statusBadge = StatusBadge(status: status);
              final actionButtons = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status != 'verified')
                    _ActionButton(
                      icon: Icons.check_circle_outline,
                      label: 'Verify',
                      color: AppColors.success,
                      onPressed: widget.onVerify,
                    ),
                  if (status != 'verified' && status != 'rejected') ...[
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.cancel_outlined,
                      label: 'Reject',
                      color: AppColors.error,
                      onPressed: widget.onReject,
                    ),
                  ],
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        avatar,
                        const SizedBox(width: 14),
                        info,
                        const SizedBox(width: 8),
                        statusBadge,
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actionButtons,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  avatar,
                  const SizedBox(width: 14),
                  info,
                  const SizedBox(width: 8),
                  statusBadge,
                  const SizedBox(width: 12),
                  actionButtons,
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textTertiary),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        backgroundColor: color.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
