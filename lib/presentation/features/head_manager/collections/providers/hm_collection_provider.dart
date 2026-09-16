// lib/presentation/features/head_manager/collections/providers/hm_collection_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmCollectionState {
  final List<CollectionAssignmentModel> items;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final String statusFilter;
  final String search;
  final String? dateFrom;
  final String? dateTo;

  const HmCollectionState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.statusFilter = 'all',
    this.search = '',
    this.dateFrom,
    this.dateTo,
  });

  HmCollectionState copyWith({
    List<CollectionAssignmentModel>? items,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    String? statusFilter,
    String? search,
    String? dateFrom,
    String? dateTo,
  }) =>
      HmCollectionState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        totalCount: totalCount ?? this.totalCount,
        statusFilter: statusFilter ?? this.statusFilter,
        search: search ?? this.search,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );
}

class HmCollectionNotifier extends StateNotifier<HmCollectionState>
    with RealtimeRefreshMixin {
  final CollectionRemoteDataSource _ds;
  HmCollectionNotifier(this._ds) : super(const HmCollectionState()) {
    bindRealtimeRefresh(['collection_assignments', 'payments'],
        refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch({int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getList(
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: page,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      if (!mounted) return;
      final items = ((res['items'] as List?) ?? [])
          .map((e) =>
              CollectionAssignmentModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final total = (res['total'] as num?)?.toInt() ?? items.length;
      state = state.copyWith(
        items: items,
        isLoading: false,
        currentPage: page,
        totalPages: total == 0 ? 1 : (total / 20).ceil(),
        totalCount: total,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setStatus(String status) {
    state = state.copyWith(statusFilter: status);
    fetch();
  }

  void setSearch(String v) {
    state = state.copyWith(search: v);
    fetch();
  }

  /// Status at/o search nang ISANG fetch lang — ginagamit kapag sabay na
  /// nagbago ang dalawa (hal. "All Pending Payment" pill na may search sa
  /// Payments module), para hindi dalawang beses mag-load.
  void setFilters({String? status, String? search}) {
    state = state.copyWith(
      statusFilter: status ?? state.statusFilter,
      search: search ?? state.search,
    );
    fetch();
  }

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
    fetch();
  }

  Future<bool> assignRider({
    required String loanScheduleId,
    required String loanId,
    required String riderId,
    String? assignmentId,
    DateTime? collectionSchedule,
    DateTime? collectionScheduleEnd,
    String notes = '',
  }) async {
    try {
      await _ds.assignCollection(
        loanScheduleId: loanScheduleId,
        riderId: riderId,
        assignmentId: assignmentId,
        collectionSchedule: collectionSchedule?.toIso8601String(),
        collectionScheduleEnd: collectionScheduleEnd?.toIso8601String(),
        notes: notes,
      );
    } catch (e) {
      // Ang totoong server error ang itago sa state (dating kinakain ito ng
      // `catch (_)` kaya generic na "Failed to assign rider" lang ang lumalabas).
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
    // Hiwalay sa mutation: hindi dapat maging "failed" ang matagumpay na
    // assign kapag nabigo lang ang refresh ng listahan.
    // SILENT + background — hindi dapat mag-loading/shimmer nang buo ang
    // data table pagkatapos mag-assign ng rider.
    if (mounted) unawaited(fetch(silent: true));
    return true;
  }

  /// Kinukumpirma na nakuha ang pera. Sa approve lang bumababa ang loan balance.
  Future<bool> approveCollection(String assignmentId) async {
    try {
      await _ds.approveCollection(assignmentId: assignmentId);
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
    // SILENT + background — hindi dapat mag-loading/shimmer nang buo ang
    // data table pagkatapos mag-assign ng rider.
    if (mounted) unawaited(fetch(silent: true));
    return true;
  }

  /// Hindi nakuha ang pera — hindi binabawasan ang loan; i-reassign ang rider.
  Future<bool> rejectCollection(String assignmentId, String reason) async {
    try {
      await _ds.rejectCollection(assignmentId: assignmentId, reason: reason);
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
    // SILENT + background — hindi dapat mag-loading/shimmer nang buo ang
    // data table pagkatapos mag-assign ng rider.
    if (mounted) unawaited(fetch(silent: true));
    return true;
  }
}

final hmCollectionProvider =
    AutoDisposeStateNotifierProvider<HmCollectionNotifier, HmCollectionState>(
  (ref) => HmCollectionNotifier(sl<CollectionRemoteDataSource>()),
);
