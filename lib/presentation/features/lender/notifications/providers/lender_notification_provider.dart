// lib/presentation/features/lender/notifications/providers/lender_notification_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/notification_remote_datasource.dart';
import '../../../../../data/models/notification_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class LenderNotificationState {
  final List<NotificationModel> notifications;
  final bool isLoading;
  final String? error;
  final int unreadCount;

  const LenderNotificationState({
    this.notifications = const [],
    this.isLoading = false,
    this.error,
    this.unreadCount = 0,
  });

  LenderNotificationState copyWith({
    List<NotificationModel>? notifications,
    bool? isLoading,
    String? error,
    int? unreadCount,
  }) =>
      LenderNotificationState(
        notifications: notifications ?? this.notifications,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        unreadCount: unreadCount ?? this.unreadCount,
      );
}

class LenderNotificationNotifier extends StateNotifier<LenderNotificationState>
    with RealtimeRefreshMixin {
  final NotificationRemoteDataSource _ds;

  LenderNotificationNotifier(this._ds)
      : super(const LenderNotificationState()) {
    bindRealtimeRefresh(['notifications'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _ds.getListWithUnread(page: 1);
      state = state.copyWith(
        notifications: result.items,
        isLoading: false,
        unreadCount: result.unreadCount,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
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
      // Re-fetch on failure so local state stays in sync with the server.
      await load();
    }
  }

  Future<void> markAllRead() async {
    try {
      await _ds.markRead();
      final updated =
          state.notifications.map((n) => n.copyWith(isRead: true)).toList();
      state = state.copyWith(notifications: updated, unreadCount: 0);
    } catch (_) {
      await load();
    }
  }

  Future<void> refresh() => load();
}

final lenderNotificationProvider = AutoDisposeStateNotifierProvider<
    LenderNotificationNotifier, LenderNotificationState>((ref) {
  return LenderNotificationNotifier(sl<NotificationRemoteDataSource>());
});
