// lib/presentation/features/rider/quota/providers/rider_quota_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/models/rider_quota_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class RiderQuotaState {
  final RiderQuotaSelf? data;
  final bool isLoading;
  final String? error;

  const RiderQuotaState({this.data, this.isLoading = false, this.error});
}

/// Rider's own quota — `collections-view?fn=my-quota`. Ang rider id ay galing
/// sa token, kaya hindi makikita ng isang rider ang quota ng iba.
class RiderQuotaNotifier extends StateNotifier<RiderQuotaState>
    with RealtimeRefreshMixin {
  final CollectionRemoteDataSource _ds;

  RiderQuotaNotifier(this._ds) : super(const RiderQuotaState()) {
    bindRealtimeRefresh(
      ['rider_quotas', 'payments', 'collection_assignments'],
      refresh: () => load(silent: true),
    );
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      state = RiderQuotaState(data: state.data, isLoading: state.data == null);
    }
    try {
      final data = await _ds.getMyQuota();
      if (!mounted) return;
      state = RiderQuotaState(data: data, isLoading: false);
    } catch (e) {
      if (!mounted || silent) return;
      state = RiderQuotaState(
        data: state.data,
        isLoading: false,
        error: ErrorHandler.handle(e).message,
      );
    }
  }
}

final riderQuotaProvider =
    AutoDisposeStateNotifierProvider<RiderQuotaNotifier, RiderQuotaState>(
  (ref) => RiderQuotaNotifier(sl<CollectionRemoteDataSource>()),
);
