// lib/presentation/features/lender/notifications/providers/lender_notification_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/notification_remote_datasource.dart';
import '../../../../../data/models/notification_model.dart';

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

class LenderNotificationNotifier
    extends StateNotifier<LenderNotificationState> {
  final NotificationRemoteDataSource _ds;

  LenderNotificationNotifier(this._ds)
      : super(const LenderNotificationState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final list = await _ds.getList(page: 1);
      final unread = list.where((n) => !n.isRead).length;
      state = state.copyWith(
        notifications: list,
        isLoading: false,
        unreadCount: unread,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> markRead(String notificationId) async {
    try {
      await _ds.markRead(notificationId: notificationId);
      final updated = state.notifications
          .map((n) => n.id == notificationId ? n.copyWith(isRead: true) : n)
          .toList();
      final unread = updated.where((n) => !n.isRead).length;
      state = state.copyWith(notifications: updated, unreadCount: unread);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await _ds.markRead();
      final updated =
          state.notifications.map((n) => n.copyWith(isRead: true)).toList();
      state = state.copyWith(notifications: updated, unreadCount: 0);
    } catch (_) {}
  }

  Future<void> refresh() => load();
}

final lenderNotificationProvider =
    StateNotifierProvider<LenderNotificationNotifier, LenderNotificationState>(
        (ref) {
  return LenderNotificationNotifier(sl<NotificationRemoteDataSource>());
});
