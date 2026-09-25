// lib/presentation/features/head_manager/loans/providers/hm_loan_history_provider.dart
//
// LOAN HISTORY TAB (Loan Records)
//
// Ang listahan ng mga lender na TAPOS nang magbayad (`completed`) at ng mga
// MALAPIT nang matapos (isang installment na lang ang natitira). Hiwalay ito sa
// `hmLoanProvider`: ang huli ay naka-status bucket (`active,approved`, etc.) at
// walang progress/total-paid na datos, samantalang ang filter ng history ay
// naka-base sa DERIVED na outstanding balance — kaya `loans-view?fn=get-history`
// ang tinatanggap nito, hindi `?fn=get-list`.
//
// Ang data layer ay role-agnostic (RemoteDataSource), kaya kapareho rin ito ng
// ginagamit ng Employee Loan Records screen.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmLoanHistoryState {
  final List<LoanModel> loans;
  final bool isLoading;
  final String? error;
  final String search;
  final String? dateFrom;
  final String? dateTo;
  final int currentPage;
  final int totalPages;
  final int totalCount;

  const HmLoanHistoryState({
    this.loans = const [],
    this.isLoading = false,
    this.error,
    this.search = '',
    this.dateFrom,
    this.dateTo,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
  });

  /// Sentinel para sa `dateFrom` / `dateTo`: iba ang "hindi ipinasa"
  /// (panatilihin ang datos) sa "ipinasang null" (i-clear ang filter) — kung
  /// `??` lang ang gamit, hindi maalis ang `date_from` / `date_to` sa query.
  static const _unset = Object();

  HmLoanHistoryState copyWith({
    List<LoanModel>? loans,
    bool? isLoading,
    String? error,
    String? search,
    Object? dateFrom = _unset,
    Object? dateTo = _unset,
    int? currentPage,
    int? totalPages,
    int? totalCount,
  }) =>
      HmLoanHistoryState(
        loans: loans ?? this.loans,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        search: search ?? this.search,
        dateFrom: dateFrom == _unset ? this.dateFrom : dateFrom as String?,
        dateTo: dateTo == _unset ? this.dateTo : dateTo as String?,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        totalCount: totalCount ?? this.totalCount,
      );
}

class HmLoanHistoryNotifier extends StateNotifier<HmLoanHistoryState>
    with RealtimeRefreshMixin {
  final LoanRemoteDataSource _ds;
  int _requestSeq = 0;

  HmLoanHistoryNotifier(this._ds) : super(const HmLoanHistoryState()) {
    // Nagbabago ang listahan kapag: naging `completed` ang loan (loans), may
    // bagong verified na bayad (payments), naipon ang installment (loan_schedules),
    // nadagdagan ng penalty (penalty_logs — bahagi ng balance), o na-release ang
    // loan (disbursements).
    bindRealtimeRefresh(
        ['loans', 'loan_schedules', 'payments', 'penalty_logs', 'disbursements'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({int page = 1, bool silent = false}) async {
    final seq = ++_requestSeq;
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getHistory(
        page: page,
        limit: 10,
        search: state.search.isEmpty ? null : state.search,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      if (seq != _requestSeq) return;
      final loans = (res['data'] as List? ?? [])
          .map((e) => LoanModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        loans: loans,
        isLoading: false,
        currentPage: meta['page'] as int? ?? 1,
        totalPages: meta['total_pages'] as int? ?? 1,
        totalCount: (meta['total'] as num?)?.toInt() ?? loans.length,
      );
    } catch (e) {
      if (seq != _requestSeq) return;
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setSearch(String q) {
    state = state.copyWith(search: q);
    load();
  }

  /// `(null, null)` = i-clear ang date filter (at i-refetch nang walang
  /// `date_from` / `date_to`).
  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
    load();
  }
}

final hmLoanHistoryProvider = AutoDisposeStateNotifierProvider<
    HmLoanHistoryNotifier, HmLoanHistoryState>(
  (ref) => HmLoanHistoryNotifier(sl<LoanRemoteDataSource>()),
);
