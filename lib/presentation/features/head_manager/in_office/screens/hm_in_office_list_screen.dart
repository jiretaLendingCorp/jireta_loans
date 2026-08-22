// lib/presentation/features/head_manager/in_office/screens/hm_in_office_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/hm_in_office_provider.dart';
import '../widgets/in_office_wizard.dart';

class HmInOfficeListScreen extends ConsumerStatefulWidget {
  const HmInOfficeListScreen({super.key});

  @override
  ConsumerState<HmInOfficeListScreen> createState() =>
      _HmInOfficeListScreenState();
}

class _HmInOfficeListScreenState extends ConsumerState<HmInOfficeListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _tabs = [
    ('all', 'All'),
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
    ref.read(hmInOfficeProvider.notifier).setStatus(_tabs[_tabCtrl.index].$1);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmInOfficeProvider);

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
                ? _buildShimmer()
                : state.applications.isEmpty
                    ? const EmptyStateWidget(
                        title: 'No Walk-in Applications',
                        message:
                            'Start a new walk-in application for lenders visiting the office',
                        icon: Icons.person_add_outlined,
                      )
                    : _buildList(state),
          ),
        ],
      ),
    );
  }

  Widget _buildList(HmInOfficeState state) {
    return RefreshIndicator(
      onRefresh: () => ref.read(hmInOfficeProvider.notifier).load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: state.applications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final app = state.applications[i];
          final createdAt = app['created_at'] != null
              ? DateTime.tryParse(app['created_at'])
              : null;
          return Container(
            key: ValueKey(app['id']),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app['lender_name'] ?? 'Walk-in Lender',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Step ${app['wizard_step'] ?? 1} of 5 • ${createdAt != null ? DateFormat('MMM d, y').format(createdAt) : ''}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                StatusBadge(status: app['status'] ?? 'submitted'),
                const SizedBox(width: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
            4,
            (i) => const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: ShimmerLoader(height: 80),
                )),
      ),
    );
  }

  void _startWizard(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => InOfficeWizard(
        applicationId: null,
        onComplete: () => ref.read(hmInOfficeProvider.notifier).load(),
      ),
    );
  }
}
