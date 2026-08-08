// lib/presentation/features/employee/kyc/screens/emp_kyc_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/emp_kyc_provider.dart';

class EmpKycListScreen extends ConsumerStatefulWidget {
  const EmpKycListScreen({super.key});
  @override
  ConsumerState<EmpKycListScreen> createState() => _EmpKycListScreenState();
}

class _EmpKycListScreenState extends ConsumerState<EmpKycListScreen> {
  final _searchCtrl = TextEditingController();
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(empKycProvider.notifier).loadList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kycState = ref.watch(empKycProvider);
    return WebScaffold(
      title: 'KYC Review',
      body: Column(children: [
        _buildFilters(),
        Expanded(
            child: kycState.when(
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
      child: Row(children: [
        Expanded(
            child: TextField(
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
              .read(empKycProvider.notifier)
              .loadList(search: v, status: _statusFilter),
        )),
        const SizedBox(width: 12),
        DropdownButton<String?>(
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
                .read(empKycProvider.notifier)
                .loadList(status: v, search: _searchCtrl.text);
          },
        ),
        const SizedBox(width: 12),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: () =>
              ref.read(empKycProvider.notifier).loadList(status: _statusFilter),
        ),
      ]),
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
        child: Column(children: [
          _buildHeader(),
          const Divider(height: 1),
          ...items.asMap().entries.map(
              (e) => _buildRow(e.value as Map<String, dynamic>, e.key.isEven)),
        ]),
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

  Widget _buildRow(Map<String, dynamic> kyc, bool isEven) {
    final lender = kyc['lender'] as Map<String, dynamic>?;
    final name =
        lender != null ? '${lender['first_name']} ${lender['last_name']}' : '—';
    final submittedAt = kyc['submitted_at'] != null
        ? DateTime.parse(kyc['submitted_at']).toDisplayDate
        : kyc['created_at'] != null
            ? DateTime.tryParse(kyc['created_at'])?.toDisplayDate ?? '—'
            : '—';
    final docCount = (kyc['document_count'] as num?)?.toInt() ?? 0;
    final status = kyc['status'] ?? 'pending';
    final lenderId =
        kyc['lender_id'] as String? ?? kyc['id'] as String? ?? '';

    return InkWell(
      onTap: () => context
          .go(RouteConstants.empKycDetails.replaceFirst(':id', lenderId)),
      child: Container(
        color:
            isEven ? Colors.white : AppColors.surfaceVariant.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Expanded(
              flex: 3,
              child: Row(children: [
                CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.info.withValues(alpha: 0.15),
                    child: const Icon(Icons.person_outline,
                        size: 16, color: AppColors.info)),
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
                      ? 'KYC Submission'
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
                if (status != 'rejected') ...[
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
    final ok = await ref.read(empKycProvider.notifier).verifyAll(
          lenderId: lenderId,
          action: action,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (action == 'verified'
                ? 'KYC documents verified'
                : 'KYC documents rejected')
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
            Text('Reject KYC'),
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
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
                ScaffoldMessenger.of(context).showSnackBar(
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
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (!mounted) return;
      final ok = await ref.read(empKycProvider.notifier).verifyAll(
            lenderId: lenderId,
            action: 'rejected',
            rejectionNotes: notesCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'KYC documents rejected' : 'Action failed'),
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
      Text('No KYC submissions found',
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
