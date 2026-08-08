// lib/presentation/shared/providers/realtime_refresh_mixin.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/realtime_service.dart';

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
      RealtimeService.instance.subscribe(table, handler);
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
