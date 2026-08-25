// lib/presentation/features/head_manager/employees/screens/hm_employee_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/edit_user_modal.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/hm_employee_provider.dart';
import '../widgets/create_employee_modal.dart';

class HmEmployeeListScreen extends ConsumerStatefulWidget {
  const HmEmployeeListScreen({super.key});

  @override
  ConsumerState<HmEmployeeListScreen> createState() =>
      _HmEmployeeListScreenState();
}

class _HmEmployeeListScreenState extends ConsumerState<HmEmployeeListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmEmployeeProvider);

    return WebScaffold(
      title: 'Employees',
      actions: [
        ElevatedButton.icon(
          onPressed: () => _showCreate(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Employee'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black87,
          ),
        ),
        const SizedBox(width: 12),
      ],
      body: Column(
        children: [
          _buildFilters(state),
          Expanded(
            child: state.isLoading
                ? _buildShimmer()
                : state.employees.isEmpty
                    ? _buildEmpty()
                    : _buildTable(state.employees),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(HmEmployeeState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search employees...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) =>
                  ref.read(hmEmployeeProvider.notifier).setSearch(v),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: state.statusFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All Status')),
              DropdownMenuItem(value: 'active', child: Text('Active')),
            ],
            onChanged: (v) =>
                ref.read(hmEmployeeProvider.notifier).setStatus(v!),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<UserModel> employees) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth =
                constraints.maxWidth < 760 ? 760.0 : constraints.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  children: [
                    _buildTableHeader(),
                    const Divider(height: 1),
                    ...employees.asMap().entries.map(
                          (e) => _buildTableRow(e.value, e.key.isEven),
                        ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    const headerStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 13,
      color: AppColors.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surfaceVariant,
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Name', style: headerStyle)),
          Expanded(flex: 2, child: Text('Email', style: headerStyle)),
          Expanded(flex: 2, child: Text('Position', style: headerStyle)),
          Expanded(flex: 1, child: Text('Status', style: headerStyle)),
          Expanded(flex: 2, child: Text('Actions', style: headerStyle)),
        ],
      ),
    );
  }

  Widget _buildTableRow(UserModel user, bool isEven) {
    final isActive = user.accountStatus == 'active';
    return Container(
      key: ValueKey(user.id),
        color: isEven
            ? Colors.white
            : AppColors.surfaceVariant.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                '${user.firstName} ${user.lastName}',
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.email ?? '—',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.position ?? '—',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 1,
              child: _StatusBadge(
                label: isActive ? 'Active' : _statusLabel(user.accountStatus),
                color: isActive ? AppColors.success : AppColors.error,
                bgColor:
                    isActive ? AppColors.successLight : AppColors.errorLight,
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  _ActionBtn(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View',
                    onTap: () => context.go(
                      RouteConstants.hmEmployeeDetails.replaceFirst(
                        ':id',
                        user.id,
                      ),
                    ),
                  ),
                  _ActionBtn(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit',
                    color: AppColors.primary,
                    onTap: () => _openEdit(user),
                  ),
                  _ActionBtn(
                    icon: Icons.archive_outlined,
                    tooltip: 'Archive',
                    color: AppColors.error,
                    onTap: () => _confirmArchive(user),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'inactive':
        return 'Inactive';
      case 'archived':
        return 'Archived';
      default:
        return 'Inactive';
    }
  }

  Widget _buildEmpty() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text(
              'No employees found',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );

  Widget _buildShimmer() => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => const ShimmerLoader(height: 56),
      );

  void _showCreate(BuildContext context) {
    showDialog(context: context, builder: (_) => const CreateEmployeeModal());
  }

  void _confirmArchive(UserModel user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Employee?'),
        content: Text(
          'This will archive ${user.firstName} ${user.lastName}. This action cannot be undone easily.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(hmEmployeeProvider.notifier).archive(user.id);
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEdit(UserModel user) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => EditUserModal(
        userId: user.id,
        initialRole: 'employee',
        initialStatus: user.accountStatus,
        showRole: false,
      ),
    );
    if (updated == true) {
      ref.read(hmEmployeeProvider.notifier).load();
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    this.color = AppColors.textSecondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      );
}
