// lib/presentation/features/head_manager/ci/providers/hm_ci_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmCiState {
  final List<CreditInvestigationModel> items;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final String statusFilter;
  final String search;

  const HmCiState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.statusFilter = 'all',
    this.search = '',
  });

  HmCiState copyWith({
    List<CreditInvestigationModel>? items,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    String? statusFilter,
    String? search,
  }) =>
      HmCiState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        totalCount: totalCount ?? this.totalCount,
        statusFilter: statusFilter ?? this.statusFilter,
        search: search ?? this.search,
      );
}

class HmCiNotifier extends StateNotifier<HmCiState> with RealtimeRefreshMixin {
  final CiRemoteDataSource _ds;

  HmCiNotifier(this._ds) : super(const HmCiState()) {
    bindRealtimeRefresh(['credit_investigations', 'ci_documents'],
        refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch({int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getList(
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        page: page,
      );
      final list = (res['data'] as List? ?? [])
          .map((e) =>
              CreditInvestigationModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        items: list,
        isLoading: false,
        currentPage: (meta['page'] as num?)?.toInt() ?? 1,
        totalPages: (meta['total_pages'] as num?)?.toInt() ?? 1,
        totalCount: (meta['total'] as num?)?.toInt() ?? list.length,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setStatus(String s) {
    state = state.copyWith(statusFilter: s);
    fetch();
  }

  Future<bool> assignCi({
    required String loanId,
    required String riderId,
    required String notes,
    required String deadline,
  }) async {
    try {
      await _ds.assignCi(
        loanId: loanId,
        riderId: riderId,
        investigationNotes: notes,
        deadline: deadline,
      );
      await fetch(page: state.currentPage);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> assignCI({
    required String loanId,
    required String riderId,
    String notes = '',
    DateTime? deadline,
  }) {
    return assignCi(
      loanId: loanId,
      riderId: riderId,
      notes: notes,
      deadline: deadline?.toIso8601String() ?? '',
    );
  }

  Future<bool> approveReport({required String ciId, String? notes}) async {
    try {
      await _ds.approveCiReport(ciId: ciId, reviewNotes: notes);
      await fetch(page: state.currentPage);
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  Future<bool> rejectReport({required String ciId, required String reason}) async {
    try {
      await _ds.rejectCiReport(ciId: ciId, rejectionReason: reason);
      await fetch(page: state.currentPage);
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
  }
}

final hmCiProvider =
    AutoDisposeStateNotifierProvider<HmCiNotifier, HmCiState>((ref) {
  return HmCiNotifier(sl<CiRemoteDataSource>());
});
