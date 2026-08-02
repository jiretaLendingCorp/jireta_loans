// lib/presentation/features/head_manager/lenders/screens/hm_lender_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../providers/hm_lender_provider.dart';
import '../widgets/create_lender_modal.dart';

class HmLenderListScreen extends ConsumerStatefulWidget {
  const HmLenderListScreen({super.key});

  @override
  ConsumerState<HmLenderListScreen> createState() => _HmLenderListScreenState();
}

class _HmLenderListScreenState extends ConsumerState<HmLenderListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmLenderProvider);
    return WebScaffold(
      title: 'Lenders',
      actions: [
        ElevatedButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const CreateLenderModal(),
          ),
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Register Lender'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.lenderPurple,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
      ],
      body: Column(
        children: [
          _filters(state),
          Expanded(
            child: state.isLoading
                ? _shimmer()
                : state.lenders.isEmpty
                ? _empty()
                : _table(state.lenders),
          ),
        ],
      ),
    );
  }

  Widget _filters(HmLenderState state) => Container(
    color: Colors.white,
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search lenders...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) => ref.read(hmLenderProvider.notifier).setSearch(v),
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<String>(
          value: state.statusFilter,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All')),
            DropdownMenuItem(value: 'active', child: Text('Active')),
            DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
          ],
          onChanged: (v) => ref.read(hmLenderProvider.notifier).setStatus(v!),
        ),
      ],
    ),
  );

  Widget _table(List<UserModel> lenders) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Card(
      child: Column(
        children: [
          _header(),
          const Divider(height: 1),
          ...lenders.asMap().entries.map((e) => _row(e.value, e.key.isEven)),
        ],
      ),
    ),
  );

  Widget _header() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    color: AppColors.surfaceVariant,
    child: const Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            'Name',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'Phone',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'KYC Status',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(
            'Status',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'Actions',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _row(UserModel user, bool isEven) {
    final isActive = user.accountStatus == 'active';
    return InkWell(
      onTap: () => context.go(
        RouteConstants.hmLenderDetails.replaceFirst(':id', user.id),
      ),
      child: Container(
        color: isEven
            ? Colors.white
            : AppColors.surfaceVariant.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.lenderPurple,
                    child: Text(
                      user.firstName.isNotEmpty
                          ? user.firstName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      '${user.firstName} ${user.lastName}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.phoneNumber ?? '—',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '—',
                  style: TextStyle(fontSize: 11, color: AppColors.info),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.successLight
                      : AppColors.errorLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? 'Active' : 'Suspended',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  _btn(
                    Icons.visibility_outlined,
                    'View',
                    AppColors.textSecondary,
                    () => context.go(
                      RouteConstants.hmLenderDetails.replaceFirst(
                        ':id',
                        user.id,
                      ),
                    ),
                  ),
                  _btn(
                    isActive
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    isActive ? 'Suspend' : 'Activate',
                    isActive ? AppColors.warning : AppColors.success,
                    () => ref
                        .read(hmLenderProvider.notifier)
                        .suspendActivate(
                          user.id,
                          isActive ? 'suspend' : 'activate',
                        ),
                  ),
                  _btn(
                    Icons.block,
                    'Blacklist',
                    AppColors.error,
                    () => _blacklistDialog(user),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, String tip, Color color, VoidCallback onTap) =>
      Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      );

  void _blacklistDialog(UserModel user) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Blacklist Lender?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Blacklisting ${user.firstName} ${user.lastName} will prevent them from applying for new loans.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
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
              await ref
                  .read(hmLenderProvider.notifier)
                  .addBlacklist(user.id, ctrl.text);
            },
            child: const Text('Blacklist'),
          ),
        ],
      ),
    );
  }

  Widget _empty() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.people_outline, size: 64, color: AppColors.textTertiary),
        SizedBox(height: 16),
        Text(
          'No lenders found',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
        ),
      ],
    ),
  );

  Widget _shimmer() => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: 6,
    separatorBuilder: (_, __) => const SizedBox(height: 8),
    itemBuilder: (_, __) => const ShimmerLoader(height: 56),
  );
}
