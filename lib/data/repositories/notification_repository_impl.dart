// lib/data/repositories/notification_repository_impl.dart
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/remote/notification_remote_datasource.dart';

class NotificationRepositoryImpl implements INotificationRepository {
  final NotificationRemoteDataSource _ds;
  NotificationRepositoryImpl(this._ds);

  @override
  Future<void> sendNotification(Map<String, dynamic> data) =>
      _ds.sendNotification(data);

  @override
  Future<List<dynamic>> getNotifications({bool? isRead, int page = 1}) =>
      _ds.getNotifications(isRead: isRead, page: page);

  @override
  Future<void> markRead({String? notificationId}) =>
      _ds.markRead(notificationId: notificationId);
}
