// lib/presentation/features/head_manager/notifications/providers/hm_notification_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/notification_remote_datasource.dart';
import '../../../../../data/models/notification_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmNotificationState {
  final List<NotificationModel> notifications;
  final List<Map<String, dynamic>> smsLogs;
  final bool isLoading;
  final String? error;
  final int unreadCount;

  const HmNotificationState({
    this.notifications = const [],
    this.smsLogs = const [],
    this.isLoading = false,
    this.error,
    this.unreadCount = 0,
  });

  HmNotificationState copyWith({
    List<NotificationModel>? notifications,
    List<Map<String, dynamic>>? smsLogs,
    bool? isLoading,
    String? error,
    int? unreadCount,
  }) =>
      HmNotificationState(
        notifications: notifications ?? this.notifications,
        smsLogs: smsLogs ?? this.smsLogs,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        unreadCount: unreadCount ?? this.unreadCount,
      );
}

class HmNotificationNotifier extends StateNotifier<HmNotificationState>
    with RealtimeRefreshMixin {
  final NotificationRemoteDataSource _ds;

  HmNotificationNotifier(this._ds) : super(const HmNotificationState()) {
    bindRealtimeRefresh(['notifications'],
        refresh: () => loadNotifications(silent: true));
    loadNotifications();
  }

  Future<void> loadNotifications({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _ds.getListWithUnread(page: 1);
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

  Future<void> markRead(String id) async {
    try {
      final isUnread =
          state.notifications.any((n) => n.id == id && !n.isRead);
      final prevUnread = state.unreadCount;
      final updated = state.notifications.map((n) {
        if (n.id == id) return n.copyWith(isRead: true);
        return n;
      }).toList();
      // Optimistic update so badge disappears instantly on tap.
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

  // Kept for backward compatibility but no longer exposed in UI.
  // Head Manager / Employee notifications are now read-only and system-driven.
  Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    String? referenceId,
  }) async {
    await _ds.send(
        userId: userId,
        title: title,
        body: body,
        type: type,
        referenceId: referenceId);
    await loadNotifications();
  }
}

final hmNotificationProvider = AutoDisposeStateNotifierProvider<
    HmNotificationNotifier, HmNotificationState>(
  (ref) => HmNotificationNotifier(sl<NotificationRemoteDataSource>()),
);
