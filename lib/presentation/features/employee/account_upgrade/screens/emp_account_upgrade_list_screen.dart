// lib/presentation/features/employee/account_upgrade/screens/emp_account_upgrade_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../providers/emp_account_upgrade_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class EmpAccountUpgradeListScreen extends ConsumerStatefulWidget {
  const EmpAccountUpgradeListScreen({super.key});
  @override
  ConsumerState<EmpAccountUpgradeListScreen> createState() =>
      _EmpAccountUpgradeListScreenState();
}

class _EmpAccountUpgradeListScreenState
    extends ConsumerState<EmpAccountUpgradeListScreen> {
  final _searchCtrl = TextEditingController();
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(empAccountUpgradeProvider.notifier).loadList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountUpgradeState = ref.watch(empAccountUpgradeProvider);
    return WebScaffold(
      title: 'Account Upgrade Review',
      body: Column(children: [
        _buildFilters(),
        Expanded(
            child: accountUpgradeState.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, __) => const ShimmerLoader(height: 60),
          ),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (data) {
            final items = (data['items'] as List?) ?? [];
            if (items.isEmpty) return _buildEmpty();
            return _buildTable(items);
          },
        )),
      ]),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by lender name...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) => ref
                .read(empAccountUpgradeProvider.notifier)
                .loadList(search: v, status: _statusFilter),
          );
          final statusDropdown = DropdownButton<String?>(
            value: _statusFilter,
            hint: const Text('All Status'),
            items: const [
              DropdownMenuItem(value: null, child: Text('All Status')),
              DropdownMenuItem(value: 'submitted', child: Text('Submitted')),
              DropdownMenuItem(value: 'verified', child: Text('Verified')),
              DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
            ],
            onChanged: (v) {
              setState(() => _statusFilter = v);
              ref
                  .read(empAccountUpgradeProvider.notifier)
                  .loadList(status: v, search: _searchCtrl.text);
            },
          );
          final refreshBtn = IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref
                .read(empAccountUpgradeProvider.notifier)
                .loadList(status: _statusFilter),
          );

          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: statusDropdown),
                  refreshBtn,
                ]),
              ],
            );
          }
          return Row(children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            statusDropdown,
            const SizedBox(width: 12),
            refreshBtn,
          ]);
        },
      ),
    );
  }

  Widget _buildTable(List items) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth =
                constraints.maxWidth < 760 ? 760.0 : constraints.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(children: [
                  _buildHeader(),
                  const Divider(height: 1),
                  ...items.asMap().entries.map((e) =>
                      _buildRow(e.value as Map<String, dynamic>, e.key.isEven)),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const s = TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surfaceVariant,
      child: const Row(children: [
        Expanded(flex: 3, child: Text('Lender', style: s)),
        Expanded(flex: 2, child: Text('Documents', style: s)),
        Expanded(flex: 2, child: Text('Submitted', style: s)),
        Expanded(flex: 1, child: Text('Status', style: s)),
        Expanded(flex: 2, child: Text('Action', style: s)),
      ]),
    );
  }

  Widget _buildRow(Map<String, dynamic> accountUpgrade, bool isEven) {
    final lender = accountUpgrade['lender'] as Map<String, dynamic>?;
    final name =
        lender != null ? '${lender['first_name']} ${lender['last_name']}' : '—';
    final submittedAt = accountUpgrade['submitted_at'] != null
        ? DateTime.parse(accountUpgrade['submitted_at']).toDisplayDate
        : accountUpgrade['created_at'] != null
            ? DateTime.tryParse(accountUpgrade['created_at'])?.toDisplayDate ??
                '—'
            : '—';
    final docCount = (accountUpgrade['document_count'] as num?)?.toInt() ?? 0;
    final status = accountUpgrade['status'] ?? 'pending';
    final lenderId = accountUpgrade['lender_id'] as String? ??
        accountUpgrade['id'] as String? ??
        '';

    return InkWell(
      key: ValueKey(accountUpgrade['id']),
      onTap: () => context.go(RouteConstants.empAccountUpgradeDetails
          .replaceFirst(':id', lenderId)),
      child: Container(
        color: isEven
            ? Colors.white
            : AppColors.surfaceVariant.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Expanded(
              flex: 3,
              child: Row(children: [
                ProfileAvatar(
                  photoUrl: lender?['profile_photo_url'] as String?,
                  name: lender?['first_name'] as String? ?? '',
                  color: AppColors.info,
                  radius: 16,
                  fallback: const Icon(Icons.person_outline,
                      size: 16, color: AppColors.info),
                ),
                const SizedBox(width: 10),
                Flexible(
                    child: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis)),
              ])),
          Expanded(
              flex: 2,
              child: Text(
                  docCount <= 0
                      ? 'Account Upgrade Submission'
                      : docCount == 1
                          ? '1 document'
                          : '$docCount documents',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary))),
          Expanded(
              flex: 2,
              child: Text(submittedAt,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary))),
          Expanded(flex: 1, child: StatusBadge(status: status)),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                if (status != 'verified')
                  _EmpActionButton(
                    label: 'Verify',
                    color: AppColors.success,
                    icon: Icons.check_circle_outline,
                    onPressed: () => _verifyAll(lenderId, 'verified'),
                  ),
                if (status != 'verified' && status != 'rejected') ...[
                  const SizedBox(width: 8),
                  _EmpActionButton(
                    label: 'Reject',
                    color: AppColors.error,
                    icon: Icons.cancel_outlined,
                    onPressed: () => _promptReject(lenderId),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _verifyAll(String lenderId, String action) async {
    final ok = await ref.read(empAccountUpgradeProvider.notifier).verifyAll(
          lenderId: lenderId,
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

  Future<void> _promptReject(String lenderId) async {
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
      final ok = await ref.read(empAccountUpgradeProvider.notifier).verifyAll(
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
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.verified_user_outlined,
          size: 64, color: AppColors.textTertiary),
      SizedBox(height: 16),
      Text('No account upgrade submissions found',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
    ]));
  }
}

class _EmpActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onPressed;

  const _EmpActionButton({
    required this.label,
    required this.color,
    required this.icon,
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
