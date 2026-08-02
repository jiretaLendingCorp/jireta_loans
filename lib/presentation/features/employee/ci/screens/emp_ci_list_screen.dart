// lib/presentation/features/employee/ci/screens/emp_ci_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../ci/providers/emp_ci_provider.dart';

class EmpCiListScreen extends ConsumerStatefulWidget {
  const EmpCiListScreen({super.key});

  @override
  ConsumerState<EmpCiListScreen> createState() => _EmpCiListScreenState();
}

class _EmpCiListScreenState extends ConsumerState<EmpCiListScreen> {
  String _search = '';
  String _statusFilter = 'all';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(empCiProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empCiProvider);

    return WebScaffold(
      title: 'Credit Investigations',
      actions: [
        IconButton(
          onPressed: () => ref.read(empCiProvider.notifier).load(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          tooltip: 'Refresh',
        ),
      ],
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: state.isLoading ? const ShimmerLoader() : _buildTable(state),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search by lender or rider name...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _statusChip('all', 'All'),
          const SizedBox(width: 6),
          _statusChip('pending', 'Pending'),
          const SizedBox(width: 6),
          _statusChip('accepted', 'Accepted'),
          const SizedBox(width: 6),
          _statusChip('in_progress', 'In Progress'),
          const SizedBox(width: 6),
          _statusChip('completed', 'Completed'),
        ],
      ),
    );
  }

  Widget _statusChip(String value, String label) {
    final isSelected = _statusFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.deepNavy : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTable(EmpCiState state) {
    var items = state.items;

    if (_search.isNotEmpty) {
      items = items.where((ci) {
        final lender = (ci['lender_name'] ?? '').toString().toLowerCase();
        final rider = (ci['rider_name'] ?? '').toString().toLowerCase();
        return lender.contains(_search) || rider.contains(_search);
      }).toList();
    }

    if (_statusFilter != 'all') {
      items = items.where((ci) => ci['status'] == _statusFilter).toList();
    }

    if (items.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.search_off,
        title: 'No Investigations Found',
        subtitle: 'No CI assignments match your current filters.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final ci = items[i];
        return _CiCard(
          ci: ci,
          onTap: () => context.go(
            RouteConstants.empCiDetails.replaceFirst(':id', ci['id'] ?? ''),
          ),
        );
      },
    );
  }
}

class _CiCard extends StatelessWidget {
  final Map<String, dynamic> ci;
  final VoidCallback onTap;

  const _CiCard({required this.ci, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = ci['status'] as String? ?? 'pending';
    final loanNumber = ci['loan_number'] as String? ?? '–';
    final lenderName = ci['lender_name'] as String? ?? '–';
    final riderName = ci['rider_name'] as String? ?? 'Unassigned';
    final deadline = ci['deadline'] as String?;
    final assignedBy = ci['assigned_by_name'] as String? ?? '–';
    final createdAt = ci['created_at'] as String?;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.search,
                color: _statusColor(status),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        loanNumber,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepNavy,
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusBadge(status: status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lender: $lenderName',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.delivery_dining,
                        size: 12,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        riderName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.person_outline,
                        size: 12,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'By: $assignedBy',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (deadline != null)
                  Text(
                    'Due: ${DateTime.parse(deadline).toDisplay()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isOverdue(deadline)
                          ? AppColors.error
                          : AppColors.textSecondary,
                      fontWeight: _isOverdue(deadline)
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  createdAt != null
                      ? DateTime.parse(createdAt).toDisplay()
                      : '–',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'in_progress':
      case 'accepted':
        return AppColors.info;
      case 'declined':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  bool _isOverdue(String deadline) {
    final dt = DateTime.tryParse(deadline);
    if (dt == null) return false;
    return dt.isBefore(DateTime.now());
  }
}
