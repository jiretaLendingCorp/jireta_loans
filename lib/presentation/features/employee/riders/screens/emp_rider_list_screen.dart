// lib/presentation/features/employee/riders/screens/emp_rider_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
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
          label: const Text('Add Rider'),
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
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
          ),
          const SizedBox(width: 12),
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
      child: Card(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            ...riders
                .asMap()
                .entries
                .map((e) => _buildRow(e.value, e.key.isEven)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const style = TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surfaceVariant,
      child: const Row(children: [
        Expanded(flex: 3, child: Text('Name', style: style)),
        Expanded(flex: 2, child: Text('Phone', style: style)),
        Expanded(flex: 2, child: Text('Vehicle', style: style)),
        Expanded(flex: 2, child: Text('Plate', style: style)),
        Expanded(flex: 2, child: Text('Status', style: style)),
        Expanded(flex: 2, child: Text('Actions', style: style)),
      ]),
    );
  }

  Widget _buildRow(UserModel rider, bool isEven) {
    return InkWell(
      key: ValueKey(rider.id),
      onTap: () => context
          .go(RouteConstants.empRiderDetails.replaceFirst(':id', rider.id)),
      child: Container(
        color: isEven
            ? Colors.white
            : AppColors.surfaceVariant.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
                flex: 3,
                child: Row(children: [
                  ProfileAvatar(
                    photoUrl: rider.profilePhotoUrl,
                    name: rider.firstName,
                    color: AppColors.riderGreen,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(rider.fullName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ])),
            Expanded(
                flex: 2,
                child: Text(rider.phoneNumber ?? '—',
                    style: const TextStyle(fontSize: 13))),
            Expanded(
                flex: 2,
                child: Text(rider.vehicleType ?? '—',
                    style: const TextStyle(fontSize: 13))),
            Expanded(
                flex: 2,
                child: Text(rider.plateNumber ?? '—',
                    style: const TextStyle(fontSize: 13))),
            Expanded(flex: 2, child: _StatusBadge(status: rider.accountStatus)),
            Expanded(
                flex: 2,
                child: Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => context.go(RouteConstants.empRiderDetails
                          .replaceFirst(':id', rider.id)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.deepNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12),
                          minimumSize: Size.zero),
                      child: const Text('View'),
                    ),
                  ],
                )),
          ],
        ),
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

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  bool get isActive => status == 'active';
  String get label {
    switch (status) {
      case 'inactive':
        return 'Inactive';
      case 'archived':
        return 'Archived';
      default:
        return status.isEmpty ? 'Inactive' : status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? AppColors.successLight : AppColors.statusRejectedBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              color: isActive ? AppColors.success : AppColors.error,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}
