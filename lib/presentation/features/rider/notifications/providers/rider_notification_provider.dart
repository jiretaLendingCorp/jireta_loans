// lib/presentation/features/rider/notifications/providers/rider_notification_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/notification_remote_datasource.dart';
import '../../../../../data/models/notification_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class RiderNotificationState {
  final List<NotificationModel> notifications;
  final bool isLoading;

  /// True habang naglo-load ng susunod na page (footer spinner ng listahan).
  final bool isLoadingMore;

  /// May mas lumang notifications pa ba (server `meta.total_pages`)?
  final bool hasMore;
  final String? error;
  final int unreadCount;

  const RiderNotificationState({
    this.notifications = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
    this.unreadCount = 0,
  });

  RiderNotificationState copyWith({
    List<NotificationModel>? notifications,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? unreadCount,
  }) =>
      RiderNotificationState(
        notifications: notifications ?? this.notifications,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: error,
        unreadCount: unreadCount ?? this.unreadCount,
      );
}

class RiderNotificationNotifier extends StateNotifier<RiderNotificationState>
    with RealtimeRefreshMixin {
  final NotificationRemoteDataSource _ds;

  RiderNotificationNotifier(this._ds) : super(const RiderNotificationState()) {
    bindRealtimeRefresh(['notifications'], refresh: () => load(silent: true));
    load();
  }

  /// Page na huling na-load (para sa [loadMore]).
  int _page = 1;

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _ds.getListWithUnread(page: 1);
      _page = 1;
      state = state.copyWith(
        notifications: result.items,
        isLoading: false,
        isLoadingMore: false,
        hasMore: result.totalPages > 1,
        unreadCount: result.unreadCount,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  /// Susunod na page ng notifications — ito ang dahilan kung bakit hindi na
  /// kailangan pang magtaka kung bakit kakaunti lang ang nakikita: dati kasi
  /// page 1 (20 items) lang ang kinukuha, kaya ang mas lumang notifications ay
  /// hindi na lumalabas sa listahan.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = _page + 1;
      final result = await _ds.getListWithUnread(page: next);
      _page = next;
      state = state.copyWith(
        notifications: [...state.notifications, ...result.items],
        isLoadingMore: false,
        hasMore: result.items.isNotEmpty && next < result.totalPages,
        unreadCount: result.unreadCount,
      );
    } catch (_) {
      // Hindi kritikal: itago na lang ang footer spinner, mananatili ang
      // nakaraang page at susubukan muli sa susunod na scroll.
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> markRead(String notificationId) async {
    try {
      final prevUnread = state.unreadCount;
      final updated = state.notifications
          .map((n) => n.id == notificationId ? n.copyWith(isRead: true) : n)
          .toList();
      final decrement =
          (state.notifications.any((n) => n.id == notificationId && !n.isRead))
              ? 1
              : 0;
      await _ds.markRead(notificationId: notificationId);
      state = state.copyWith(
        notifications: updated,
        unreadCount: (prevUnread - decrement).clamp(0, prevUnread),
        error: null,
      );
    } catch (_) {
      await load();
    }
  }

  Future<void> markAllRead() async {
    try {
      // Optimistic update — badge disappears instantly when bell icon is tapped.
      final prevNotifications = state.notifications;
      state = state.copyWith(
        notifications: prevNotifications.map((n) => n.copyWith(isRead: true)).toList(),
        unreadCount: 0,
      );
      await _ds.markRead();
    } catch (_) {
      await load(silent: true);
    }
  }

  Future<void> refresh() => load();
}

final riderNotificationProvider = AutoDisposeStateNotifierProvider<
    RiderNotificationNotifier, RiderNotificationState>((ref) {
  return RiderNotificationNotifier(sl<NotificationRemoteDataSource>());
});
