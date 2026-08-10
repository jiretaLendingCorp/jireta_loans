// lib/presentation/features/head_manager/payments/screens/hm_penalty_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/models/penalty_log_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class _PenaltyState {
  final List<PenaltyLogModel> items;
  final bool isLoading;
  final String? error;
  const _PenaltyState(
      {this.items = const [], this.isLoading = false, this.error});
  _PenaltyState copyWith(
          {List<PenaltyLogModel>? items, bool? isLoading, String? error}) =>
      _PenaltyState(
          items: items ?? this.items,
          isLoading: isLoading ?? this.isLoading,
          error: error);
}

class _PenaltyNotifier extends StateNotifier<_PenaltyState>
    with RealtimeRefreshMixin<_PenaltyState> {
  final LoanRemoteDataSource _ds;
  _PenaltyNotifier(this._ds) : super(const _PenaltyState()) {
    bindRealtimeRefresh(['penalty_logs'], refresh: () => load());
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _ds.getPenaltyLogs();
      state = state.copyWith(items: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final _penaltyProvider =
    AutoDisposeStateNotifierProvider<_PenaltyNotifier, _PenaltyState>((ref) {
  return _PenaltyNotifier(sl<LoanRemoteDataSource>());
});

class HmPenaltyListScreen extends ConsumerWidget {
  const HmPenaltyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_penaltyProvider);
    return WebScaffold(
      title: 'Penalties',
      actions: [
        IconButton(
          onPressed: () => ref.read(_penaltyProvider.notifier).load(),
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          tooltip: 'Refresh',
        ),
      ],
      body: state.isLoading
          ? const Center(child: ShimmerLoader())
          : state.items.isEmpty
              ? const EmptyStateWidget(message: 'No penalties recorded yet.')
              : _buildTable(state.items),
    );
  }

  Widget _buildTable(List<PenaltyLogModel> items) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E5E5)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(children: [
          _buildHeader(),
          const Divider(height: 1),
          ...items.map((p) => _buildRow(p))
        ]),
      ),
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: const Row(children: [
          Expanded(
              flex: 2,
              child: Text('Loan #',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12))),
          Expanded(
              flex: 2,
              child: Text('Lender',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12))),
          Expanded(
              flex: 2,
              child: Text('Applied By',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12))),
          Expanded(
              flex: 1,
              child: Text('Basis',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12))),
          Expanded(
              flex: 1,
              child: Text('Penalty',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12))),
          Expanded(
              flex: 1,
              child: Text('Date',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12))),
        ]),
      );

  Widget _buildRow(PenaltyLogModel p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
        child: Row(children: [
          Expanded(
              flex: 2,
              child: Text(p.loanNumber ?? p.loanId.substring(0, 8),
                  style: const TextStyle(
                      color: AppColors.deepNavy, fontWeight: FontWeight.w500))),
          Expanded(
              flex: 2,
              child: Text(p.lenderName ?? 'N/A',
                  style: const TextStyle(color: AppColors.textSecondary))),
          Expanded(
              flex: 2,
              child: Text(p.appliedByName ?? 'N/A',
                  style: const TextStyle(color: AppColors.textSecondary))),
          Expanded(
              flex: 1,
              child: Text(p.basisAmount.toCurrency,
                  style: const TextStyle(color: AppColors.textPrimary))),
          Expanded(
              flex: 1,
              child: Text(p.penaltyAmount.toCurrency,
                  style: const TextStyle(
                      color: AppColors.error, fontWeight: FontWeight.w600))),
          Expanded(
              flex: 1,
              child: Text(DateFormat('MMM dd, yyyy').format(p.createdAt),
                  style: const TextStyle(color: AppColors.textSecondary))),
        ]),
      );
}
