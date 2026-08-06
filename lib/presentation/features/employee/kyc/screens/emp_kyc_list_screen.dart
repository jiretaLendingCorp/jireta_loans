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
        Expanded(flex: 2, child: Text('Doc Type', style: s)),
        Expanded(flex: 2, child: Text('Submitted', style: s)),
        Expanded(flex: 1, child: Text('Status', style: s)),
        Expanded(flex: 1, child: Text('Action', style: s)),
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

    return InkWell(
      onTap: () => context.go(RouteConstants.empKycDetails
          .replaceFirst(':id', kyc['lender_id'] as String? ?? kyc['id'] as String? ?? '')),
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
              child: Text(kyc['document_type'] ?? kyc['doc_type'] ?? '—',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary))),
          Expanded(
              flex: 2,
              child: Text(submittedAt,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary))),
          Expanded(
              flex: 1, child: StatusBadge(status: kyc['status'] ?? 'pending')),
          Expanded(
              flex: 1,
              child: IconButton(
                icon: const Icon(Icons.visibility_outlined,
                    size: 18, color: AppColors.info),
                tooltip: 'Review',
                onPressed: () => context.go(RouteConstants.empKycDetails
                    .replaceFirst(':id', kyc['lender_id'] as String? ?? kyc['id'] as String? ?? '')),
              )),
        ]),
      ),
    );
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
