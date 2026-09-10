// lib/presentation/features/head_manager/payments/screens/hm_penalty_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import 'package:intl/intl.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/models/penalty_log_model.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
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
    bindRealtimeRefresh(['penalty_logs'], refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final list = await _ds.getPenaltyLogs();
      state = state.copyWith(items: list, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
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
      child: ResponsiveListCard(
        minTableWidth: 820,
        variant: ResponsiveListVariant.card,
        headerTextStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            fontSize: 12),
        headerColor: Colors.transparent,
        headerPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        rowPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        rowBorder: const Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
        outerBorder: Border.all(color: const Color(0xFFE5E5E5)),
        outerShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
        columns: const [
          ResponsiveCol('Loan #', flex: 2),
          ResponsiveCol('Lender', flex: 2),
          ResponsiveCol('Applied By', flex: 2),
          ResponsiveCol('Basis', flex: 1),
          ResponsiveCol('Penalty', flex: 1),
          ResponsiveCol('Date', flex: 1),
        ],
        rows: items.map((p) => _buildRow(p)).toList(),
      ),
    );
  }

  ResponsiveRow _buildRow(PenaltyLogModel p) => ResponsiveRow(
        cells: [
          Text(p.loanNumber ?? p.loanId.substring(0, 8),
              style: const TextStyle(
                  color: AppColors.deepNavy, fontWeight: FontWeight.w500)),
          Text(p.lenderName ?? 'N/A',
              style: const TextStyle(color: AppColors.textSecondary)),
          Text(p.appliedByName ?? 'N/A',
              style: const TextStyle(color: AppColors.textSecondary)),
          Text(p.basisAmount.toCurrency,
              style: const TextStyle(color: AppColors.textPrimary)),
          Text(p.penaltyAmount.toCurrency,
              style: const TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w600)),
          Text(DateFormat('MMM dd, yyyy h:mm a').format(p.createdAt),
              style: const TextStyle(color: AppColors.textSecondary)),
        ],
      );
}
