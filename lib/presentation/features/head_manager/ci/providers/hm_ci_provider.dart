// lib/presentation/features/head_manager/ci/providers/hm_ci_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/models/credit_investigation_model.dart';

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

class HmCiNotifier extends StateNotifier<HmCiState> {
  final CiRemoteDataSource _ds;

  HmCiNotifier(this._ds) : super(const HmCiState()) {
    fetch();
  }

  Future<void> fetch({int page = 1}) async {
    state = state.copyWith(isLoading: true, error: null);
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
      state = state.copyWith(isLoading: false, error: e.toString());
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
}

final hmCiProvider = StateNotifierProvider<HmCiNotifier, HmCiState>((ref) {
  return HmCiNotifier(sl<CiRemoteDataSource>());
});
