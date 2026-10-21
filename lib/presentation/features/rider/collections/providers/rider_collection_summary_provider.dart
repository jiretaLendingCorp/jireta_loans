// lib/presentation/features/rider/collections/providers/rider_collection_summary_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/models/rider_collection_monitoring_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class RiderCollectionSummaryState {
  final RiderMonitoringSummary summary;
  final bool isLoading;
  final String? error;

  const RiderCollectionSummaryState({
    this.summary = const RiderMonitoringSummary(),
    this.isLoading = false,
    this.error,
  });
}

/// Rider's own totals — galing sa `collections-view?fn=my-collection-summary`
/// kung saan ang rider id ay galing sa token (hindi sa client parameter).
class RiderCollectionSummaryNotifier
    extends StateNotifier<RiderCollectionSummaryState>
    with RealtimeRefreshMixin {
  final CollectionRemoteDataSource _ds;

  RiderCollectionSummaryNotifier(this._ds)
      : super(const RiderCollectionSummaryState()) {
    bindRealtimeRefresh(
      ['collection_assignments', 'payments'],
      refresh: () => load(silent: true),
    );
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      state = RiderCollectionSummaryState(
        summary: state.summary,
        isLoading: state.summary.expectedCollection == 0 &&
            state.summary.confirmedCollection == 0,
      );
    }
    try {
      final summary = await _ds.getMyCollectionSummary();
      if (!mounted) return;
      state = RiderCollectionSummaryState(summary: summary, isLoading: false);
    } catch (e) {
      if (!mounted || silent) return;
      state = RiderCollectionSummaryState(
        summary: state.summary,
        isLoading: false,
        error: ErrorHandler.handle(e).message,
      );
    }
  }
}

final riderCollectionSummaryProvider = AutoDisposeStateNotifierProvider<
    RiderCollectionSummaryNotifier, RiderCollectionSummaryState>(
  (ref) => RiderCollectionSummaryNotifier(sl<CollectionRemoteDataSource>()),
);
