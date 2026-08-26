// lib/presentation/features/employee/collections/providers/emp_collection_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpCollectionState {
  final List<CollectionAssignmentModel> items;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final String statusFilter;

  const EmpCollectionState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.statusFilter = 'all',
  });

  EmpCollectionState copyWith({
    List<CollectionAssignmentModel>? items,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    String? statusFilter,
  }) =>
      EmpCollectionState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        totalCount: totalCount ?? this.totalCount,
        statusFilter: statusFilter ?? this.statusFilter,
      );
}

class EmpCollectionNotifier extends StateNotifier<EmpCollectionState>
    with RealtimeRefreshMixin {
  final CollectionRemoteDataSource _ds;
  final UserRemoteDataSource _userDs;

  EmpCollectionNotifier(this._ds, this._userDs)
      : super(const EmpCollectionState()) {
    bindRealtimeRefresh(['collection_assignments', 'payments'],
        refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch({int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
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
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  // Legacy alias
  Future<void> loadList(
      {String? status, String? riderId, int page = 1, bool silent = false}) async {
    if (status != null) state = state.copyWith(statusFilter: status);
    await fetch(page: page, silent: silent);
  }

  void setStatus(String status) {
    state = state.copyWith(statusFilter: status);
    fetch();
  }

  Future<bool> assignRider({
    required String loanScheduleId,
    required String loanId,
    required String riderId,
    String? assignmentId,
    DateTime? collectionSchedule,
    String notes = '',
  }) async {
    try {
      await _ds.assignCollection(
        loanScheduleId: loanScheduleId,
        riderId: riderId,
        assignmentId: assignmentId,
        collectionSchedule: collectionSchedule?.toIso8601String(),
        notes: notes,
      );
      await fetch();
      return true;
    } catch (_) {
      return false;
    }
  }

  // Legacy assign signature
  Future<bool> assign(
      {required String loanScheduleId,
      String? assignmentId,
      required String riderId,
      String? notes,
      String? schedule}) {
    return assignRider(
      loanScheduleId: loanScheduleId,
      loanId: '',
      riderId: riderId,
      assignmentId: assignmentId,
      collectionSchedule:
          schedule != null ? DateTime.tryParse(schedule) : null,
      notes: notes ?? '',
    );
  }

  Future<List<Map<String, dynamic>>> getAvailableRiders() async {
    try {
      final data = await _userDs.getList(
          role: 'rider', status: 'active', page: 1, limit: 100);
      return List<Map<String, dynamic>>.from(data['items'] ?? []);
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getDetail(String collectionId) async {
    try {
      final res = await _ds.getList(page: 1, limit: 1000);
      final items = (res['items'] as List?) ?? [];
      for (final it in items) {
        if (it is Map && it['id'] == collectionId) {
          return Map<String, dynamic>.from(it);
        }
      }
      // Fallback to fetch all via getCollectionList then map
      final list = await _ds.getCollectionList(limit: 1000);
      for (final c in list) {
        if (c.id == collectionId) {
          // Convert model to map-like for legacy callers if needed, but details screen now uses model provider
          return {
            'id': c.id,
            'loan_schedule_id': c.loanScheduleId,
            'status': c.status,
            'collection_type': c.collectionType,
            'amount_collected': c.amountCollected,
            'notes': c.notes,
            'collection_schedule': c.collectionSchedule?.toIso8601String(),
            'response_at': c.responseAt?.toIso8601String(),
            'completed_at': c.completedAt?.toIso8601String(),
            'proof_photo': c.proofPhoto,
            'borrower_signature': c.borrowerSignature,
            'collection_photo': c.collectionPhoto,
            'location_lat': c.locationLat,
            'location_lng': c.locationLng,
            'idempotency_key': c.idempotencyKey,
            'created_at': c.createdAt.toIso8601String(),
            'loan_schedule': c.loanSchedule,
            'rider': c.rider,
            'loan_number': c.loanNumber,
            'lender_name': c.lenderName,
            'rider_name': c.riderName,
          };
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

// Primary provider mirroring HM
final empCollectionProvider =
    AutoDisposeStateNotifierProvider<EmpCollectionNotifier, EmpCollectionState>(
  (ref) => EmpCollectionNotifier(
      sl<CollectionRemoteDataSource>(), sl<UserRemoteDataSource>()),
);

// Legacy provider alias for old code that expects AsyncValue<Map>
final empCollectionListProvider = empCollectionProvider;
