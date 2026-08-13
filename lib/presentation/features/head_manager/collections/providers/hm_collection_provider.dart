// lib/presentation/features/head_manager/collections/providers/hm_collection_provider.dart
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

  const HmCollectionState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.statusFilter = 'all',
  });

  HmCollectionState copyWith({
    List<CollectionAssignmentModel>? items,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    String? statusFilter,
  }) =>
      HmCollectionState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        totalCount: totalCount ?? this.totalCount,
        statusFilter: statusFilter ?? this.statusFilter,
      );
}

class HmCollectionNotifier extends StateNotifier<HmCollectionState>
    with RealtimeRefreshMixin {
  final CollectionRemoteDataSource _ds;
  HmCollectionNotifier(this._ds) : super(const HmCollectionState()) {
    bindRealtimeRefresh(['collection_assignments', 'payments'], refresh: fetch);
    fetch();
  }

  Future<void> fetch({int page = 1}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final list = await _ds.getCollectionList(
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        page: page,
      );
      state = state.copyWith(
        items: list,
        isLoading: false,
        currentPage: page,
        totalPages: list.length < 20 ? page : page + 1,
        totalCount: list.length + (page - 1) * 20,
      );
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setStatus(String status) {
    state = state.copyWith(statusFilter: status);
    fetch();
  }

  Future<bool> assignRider({
    required String loanScheduleId,
    required String loanId,
    required String riderId,
    DateTime? collectionSchedule,
    String notes = '',
  }) async {
    try {
      await _ds.assignCollection(
        loanScheduleId: loanScheduleId,
        riderId: riderId,
        collectionSchedule: collectionSchedule?.toIso8601String(),
        notes: notes,
      );
      await fetch();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final hmCollectionProvider =
    AutoDisposeStateNotifierProvider<HmCollectionNotifier, HmCollectionState>(
  (ref) => HmCollectionNotifier(sl<CollectionRemoteDataSource>()),
);
