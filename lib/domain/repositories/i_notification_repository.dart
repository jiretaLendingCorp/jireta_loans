// lib/domain/repositories/i_notification_repository.dart
abstract class INotificationRepository {
  Future<void> sendNotification(Map<String, dynamic> data);
  Future<List<dynamic>> getNotifications({bool? isRead, int page});
  Future<void> markRead({String? notificationId});
}
