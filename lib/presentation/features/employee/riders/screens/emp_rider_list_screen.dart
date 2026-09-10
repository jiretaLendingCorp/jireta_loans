// lib/presentation/features/employee/riders/screens/emp_rider_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/details/user_details_modal.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/search_date_filter.dart';
import '../../../../shared/widgets/search_results_chip.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../providers/emp_rider_provider.dart';
import '../widgets/emp_create_rider_modal.dart';

class EmpRiderListScreen extends ConsumerStatefulWidget {
  const EmpRiderListScreen({super.key});

  @override
  ConsumerState<EmpRiderListScreen> createState() => _EmpRiderListScreenState();
}

class _EmpRiderListScreenState extends ConsumerState<EmpRiderListScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;

  void _onDateRangeChanged(DateTimeRange? r) {
    setState(() => _dateRange = r);
    ref.read(empRiderProvider.notifier).setDateRange(
          r == null ? null : SearchDateFilter.fromParam(r.start),
          r == null ? null : SearchDateFilter.toParam(r.end),
        );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(empRiderProvider);

    return WebScaffold(
      title: 'Riders',
      actions: [
        ElevatedButton.icon(
          onPressed: () => showDialog(
              context: context, builder: (_) => const EmpCreateRiderModal()),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Create Rider'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.riderGreen,
              foregroundColor: Colors.white),
        ),
        const SizedBox(width: 12),
      ],
      body: Column(
        children: [
          _buildFilters(state),
          Expanded(
            child: state.isLoading
                ? _buildShimmer()
                : state.riders.isEmpty
                    ? _buildEmpty()
                    : _buildTable(state.riders),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(EmpRiderState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: ResponsiveSearchToolbar(
        searchField: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search riders...',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border)),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (v) =>
              ref.read(empRiderProvider.notifier).setSearch(v),
        ),
        trailing: [
          SearchDateFilter(value: _dateRange, onChanged: _onDateRangeChanged),
          SearchResultsChip(count: state.riders.length),
          DropdownButton<String>(
            value: state.statusFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All Status')),
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
            ],
            onChanged: (v) => ref.read(empRiderProvider.notifier).setStatus(v!),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<UserModel> riders) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ResponsiveListCard(
        minTableWidth: 820,
        variant: ResponsiveListVariant.card,
        columns: const [
          ResponsiveCol('Name', flex: 3),
          ResponsiveCol('Phone', flex: 2),
          ResponsiveCol('Vehicle', flex: 2),
          ResponsiveCol('Plate', flex: 2),
          ResponsiveCol('Status', flex: 2),
        ],
        actionsCol: const ResponsiveActionsCol(label: 'Actions', flex: 2),
        rows: riders.map((e) => _buildRow(e)).toList(),
      ),
    );
  }

  ResponsiveRow _buildRow(UserModel rider) {
    return ResponsiveRow(
      onTap: () => showUserDetailsModal(context, rider),
      cells: [
        Row(children: [
          ProfileAvatar(
            photoUrl: rider.profilePhotoUrl,
            name: '${rider.firstName} ${rider.lastName}',
            color: AppColors.riderGreen,
            radius: 18,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(rider.fullName,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        Text(rider.phoneNumber ?? '—',
            style: const TextStyle(fontSize: 13)),
        Text(rider.vehicleType ?? '—',
            style: const TextStyle(fontSize: 13)),
        Text(rider.plateNumber ?? '—',
            style: const TextStyle(fontSize: 13)),
        Text(
          rider.accountStatus == 'active'
              ? 'Active'
              : rider.accountStatus == 'archived'
                  ? 'Archived'
                  : 'Inactive',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: rider.accountStatus == 'active'
                ? AppColors.success
                : AppColors.error,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'View',
            child: InkWell(
              onTap: () => showUserDetailsModal(context, rider),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.visibility_outlined,
                    size: 16, color: AppColors.deepNavy),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.directions_bike_outlined,
              size: 64, color: AppColors.textTertiary),
          SizedBox(height: 16),
          Text('No riders found',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
        ]),
      );

  Widget _buildShimmer() => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => const ShimmerLoader(height: 56),
      );
}
