// lib/presentation/features/employee/notifications/providers/emp_notification_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/notification_remote_datasource.dart';
import '../../../../../data/models/notification_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpNotificationState {
  final List<NotificationModel> notifications;
  final bool isLoading;
  final String? error;
  final int unreadCount;

  const EmpNotificationState({
    this.notifications = const [],
    this.isLoading = false,
    this.error,
    this.unreadCount = 0,
  });

  EmpNotificationState copyWith({
    List<NotificationModel>? notifications,
    bool? isLoading,
    String? error,
    int? unreadCount,
  }) =>
      EmpNotificationState(
        notifications: notifications ?? this.notifications,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        unreadCount: unreadCount ?? this.unreadCount,
      );
}

class EmpNotificationNotifier extends StateNotifier<EmpNotificationState>
    with RealtimeRefreshMixin {
  final NotificationRemoteDataSource _ds;
  EmpNotificationNotifier(this._ds) : super(const EmpNotificationState()) {
    bindRealtimeRefresh(['notifications'],
        refresh: () => loadNotifications(silent: true));
    loadNotifications();
  }

  Future<void> loadNotifications(
      {bool? isRead, int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final result =
          await _ds.getListWithUnread(isRead: isRead, page: page);
      state = state.copyWith(
        notifications: result.items,
        unreadCount: result.unreadCount,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  /// Backwards-compatible alias – delegates to [loadNotifications].
  Future<void> loadList(
          {bool? isRead, int page = 1, bool silent = false}) =>
      loadNotifications(isRead: isRead, page: page, silent: silent);

  Future<void> markRead({String? id}) async {
    // Mark all when id is null
    if (id == null) return markAllRead();
    try {
      final isUnread =
          state.notifications.any((n) => n.id == id && !n.isRead);
      final prevUnread = state.unreadCount;
      final updated = state.notifications
          .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
          .toList();
      state = state.copyWith(
        notifications: updated,
        unreadCount:
            isUnread ? (prevUnread - 1).clamp(0, prevUnread) : prevUnread,
      );
      await _ds.markRead(notificationId: id);
    } catch (_) {
      await loadNotifications(silent: true);
    }
  }

  Future<void> markAllRead() async {
    try {
      state = state.copyWith(
        notifications:
            state.notifications.map((n) => n.copyWith(isRead: true)).toList(),
        unreadCount: 0,
      );
      await _ds.markRead();
    } catch (_) {
      await loadNotifications(silent: true);
    }
  }

  Future<void> refresh() => loadNotifications();
}

final empNotificationProvider = AutoDisposeStateNotifierProvider<
    EmpNotificationNotifier, EmpNotificationState>((ref) {
  return EmpNotificationNotifier(sl<NotificationRemoteDataSource>());
});
