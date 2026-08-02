// lib/presentation/features/head_manager/notifications/providers/hm_notification_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/notification_remote_datasource.dart';
import '../../../../../data/models/notification_model.dart';

class HmNotificationState {
  final List<NotificationModel> notifications;
  final List<Map<String, dynamic>> smsLogs;
  final bool isLoading;
  final String? error;

  const HmNotificationState({
    this.notifications = const [],
    this.smsLogs = const [],
    this.isLoading = false,
    this.error,
  });

  HmNotificationState copyWith({
    List<NotificationModel>? notifications,
    List<Map<String, dynamic>>? smsLogs,
    bool? isLoading,
    String? error,
  }) =>
      HmNotificationState(
        notifications: notifications ?? this.notifications,
        smsLogs: smsLogs ?? this.smsLogs,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class HmNotificationNotifier extends StateNotifier<HmNotificationState> {
  final NotificationRemoteDataSource _ds;

  HmNotificationNotifier(this._ds) : super(const HmNotificationState()) {
    loadNotifications();
  }

  Future<void> loadNotifications() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _ds.getList(page: 1);
      state = state.copyWith(notifications: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _ds.markRead(notificationId: id);
      final updated = state.notifications.map((n) {
        if (n.id == id) return n.copyWith(isRead: true);
        return n;
      }).toList();
      state = state.copyWith(notifications: updated);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await _ds.markRead();
      final updated =
          state.notifications.map((n) => n.copyWith(isRead: true)).toList();
      state = state.copyWith(notifications: updated);
    } catch (_) {}
  }

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

final hmNotificationProvider =
    StateNotifierProvider<HmNotificationNotifier, HmNotificationState>(
  (ref) => HmNotificationNotifier(sl<NotificationRemoteDataSource>()),
);
