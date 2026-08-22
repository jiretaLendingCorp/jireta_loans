// lib/presentation/features/lender/dashboard/providers/lender_rider_tracking_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/location_remote_datasource.dart';
import '../../../../../data/models/tracked_rider_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

/// Live rider tracking state for the lender home screen.
class LenderRiderTrackingState {
  final List<TrackedRiderModel> riders;
  final bool isLoading;
  final String? error;

  const LenderRiderTrackingState({
    this.riders = const [],
    this.isLoading = false,
    this.error,
  });

  LenderRiderTrackingState copyWith({
    List<TrackedRiderModel>? riders,
    bool? isLoading,
    String? error,
  }) =>
      LenderRiderTrackingState(
        riders: riders ?? this.riders,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

/// Loads the list of riders a lender may currently track (only assignments the
/// rider has ACCEPTED: an unrecorded collection, a CI, or an in-flight
/// rider-delivery disbursement — collections drop out once recorded, i.e. the
/// moment the rider has taken the amount from the lender) and keeps it live
/// via realtime.
///
/// Realtime sources:
///  - `rider_locations`      → rider moved (GPS push every ~30s)
///  - `collection_assignments` / `credit_investigations` / `disbursements`
///    → a rider accepted a new assignment (rider appears) or finished one
///    (rider disappears). Debounced by [RealtimeService].
class LenderRiderTrackingNotifier extends StateNotifier<LenderRiderTrackingState>
    with RealtimeRefreshMixin {
  final LocationRemoteDataSource _ds;

  LenderRiderTrackingNotifier(this._ds)
      : super(const LenderRiderTrackingState()) {
    bindRealtimeRefresh(
      ['rider_locations', 'collection_assignments', 'credit_investigations', 'disbursements'],
      refresh: () => load(silent: true),
    );
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final riders = await _ds.getTrackedRiders();
      state = state.copyWith(riders: riders, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
        isLoading: false,
        error: ErrorHandler.handle(e).message,
      );
    }
  }

  Future<void> refresh() => load();
}

final lenderRiderTrackingProvider = AutoDisposeStateNotifierProvider<
    LenderRiderTrackingNotifier, LenderRiderTrackingState>((ref) {
  return LenderRiderTrackingNotifier(sl<LocationRemoteDataSource>());
});
