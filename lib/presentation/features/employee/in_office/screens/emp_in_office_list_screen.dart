// lib/presentation/features/employee/in_office/screens/emp_in_office_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/emp_in_office_provider.dart';
import '../../../../../presentation/features/head_manager/in_office/widgets/in_office_wizard.dart';

class EmpInOfficeListScreen extends ConsumerStatefulWidget {
  const EmpInOfficeListScreen({super.key});

  @override
  ConsumerState<EmpInOfficeListScreen> createState() =>
      _EmpInOfficeListScreenState();
}

class _EmpInOfficeListScreenState extends ConsumerState<EmpInOfficeListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _tabs = [
    ('all', 'All'),
    ('draft', 'Draft'),
    ('submitted', 'Submitted'),
    ('converted', 'Converted'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabCtrl.indexIsChanging) return;
    ref.read(empInOfficeProvider.notifier).setStatus(_tabs[_tabCtrl.index].$1);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _startWizard(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => InOfficeWizard(
        applicationId: null,
        onComplete: () {
          ref.read(empInOfficeProvider.notifier).loadList();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empInOfficeProvider);
    final items = state.valueOrNull?['items'] as List? ?? [];

    return WebScaffold(
      title: 'Walk-in Applications',
      actions: [
        ElevatedButton.icon(
          onPressed: () => _startWizard(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Walk-in'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black87,
          ),
        ),
        const SizedBox(width: 12),
      ],
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.deepNavy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerLoader()
                : items.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.person_add_outlined,
                        title: 'No walk-in applications',
                        subtitle: 'Start a new in-office application above.',
                      )
                    : _ApplicationList(items: items),
          ),
        ],
      ),
    );
  }
}

class _ApplicationList extends StatelessWidget {
  final List items;
  const _ApplicationList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final app = items[i] as Map<String, dynamic>;
        final lenderName = app['lender_name'] as String? ?? 'New Applicant';
        final status = app['status'] as String? ?? 'draft';
        final step = app['wizard_step'] as int? ?? 1;
        final createdAt = app['created_at'] as String?;

        return Card(
          key: ValueKey(app['id']),
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.deepNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.assignment_outlined,
                      color: AppColors.deepNavy, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lenderName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          StatusBadge(status: status),
                          const SizedBox(width: 8),
                          if (status == 'draft')
                            Text('Step $step/5',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary)),
                        ],
                      ),
                      if (createdAt != null)
                        Text('Created: $createdAt',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                if (status == 'draft')
                  OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.deepNavy),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                    child: const Text('Continue',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.deepNavy)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
