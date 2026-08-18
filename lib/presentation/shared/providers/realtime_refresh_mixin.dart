// lib/presentation/shared/providers/realtime_refresh_mixin.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/utils/logger.dart';

/// Binds a [StateNotifier] to live changes on one or more database tables.
///
/// On any INSERT/UPDATE/DELETE in a bound table, the [refresh] callback is
/// invoked (debounced by [RealtimeService]) so the provider re-fetches its data
/// without a manual pull-to-refresh.
mixin RealtimeRefreshMixin<T> on StateNotifier<T> {
  final Map<String, List<void Function()>> _realtimeBindings = {};

  void bindRealtimeRefresh(
    List<String> tables, {
    required Future<void> Function() refresh,
  }) {
    for (final table in tables) {
      void handler() {
        if (mounted) refresh();
      }

      _realtimeBindings.putIfAbsent(table, () => []).add(handler);
      // Real-time is a best-effort enhancement: if the socket/session is not
      // ready (e.g. tests, offline, no stored session) the provider must still
      // work via the manual refresh button. Guard the async subscribe so an
      // unhandled exception can never break a screen's initial load.
      unawaited(_safeSubscribe(table, handler));
    }
  }

  Future<void> _safeSubscribe(String table, void Function() handler) async {
    try {
      await RealtimeService.instance.subscribe(table, handler);
    } catch (e) {
      AppLogger.debug('[Realtime] Subscribe failed for $table: $e');
    }
  }

  @override
  void dispose() {
    for (final entry in _realtimeBindings.entries) {
      for (final handler in entry.value) {
        RealtimeService.instance.unsubscribe(entry.key, handler);
      }
    }
    _realtimeBindings.clear();
    super.dispose();
  }
}
