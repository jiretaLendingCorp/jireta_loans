// lib/data/datasources/remote/notification_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/notification_model.dart';

class NotificationRemoteDataSource {
  final DioClient _client;
  NotificationRemoteDataSource(this._client);

  Future<List<NotificationModel>> getList({bool? isRead, int page = 1}) async {
    final res = await _client.get(
      ApiEndpoints.notificationsGetList,
      queryParams: {
        if (isRead != null) 'is_read': isRead,
        'page': page,
        'limit': 20,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns the notification list along with the server-authoritative
  /// unread count. The server counts unread across ALL pages, so relying on it
  /// (instead of counting the first page only) keeps the bell badge accurate.
  Future<({List<NotificationModel> items, int unreadCount})> getListWithUnread({
    bool? isRead,
    int page = 1,
  }) async {
    final res = await _client.get(
      ApiEndpoints.notificationsGetList,
      queryParams: {
        if (isRead != null) 'is_read': isRead,
        'page': page,
        'limit': 20,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    final unread = (res.data['unread_count'] as num?)?.toInt() ?? 0;
    return (
      items: list
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      unreadCount: unread,
    );
  }

  Future<Map<String, dynamic>> getListMap({bool? isRead, int page = 1}) async {
    final res = await _client.get(
      ApiEndpoints.notificationsGetList,
      queryParams: {
        if (isRead != null) 'is_read': isRead,
        'page': page,
        'limit': 20,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return {
      'items': list,
      'total': (res.data['total'] as num?)?.toInt() ?? list.length,
    };
  }

  Future<void> markRead({String? notificationId}) async {
    await _client.patch(
      ApiEndpoints.notificationsMarkRead,
      data: {
        if (notificationId != null) 'notification_id': notificationId,
        if (notificationId == null) 'mark_all': true,
      },
    );
  }

  Future<void> send({
    required String userId,
    required String title,
    required String body,
    required String type,
    String? referenceId,
  }) async {
    await _client.post(
      ApiEndpoints.notificationsSend,
      data: {
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
        if (referenceId != null) 'reference_id': referenceId,
      },
    );
  }

  Future<List<NotificationModel>> getNotifications({
    bool? isRead,
    int page = 1,
  }) =>
      getList(isRead: isRead, page: page);

  Future<void> sendNotification(Map<String, dynamic> data) => send(
        userId: (data['userId'] ?? data['user_id'] ?? '').toString(),
        title: (data['title'] ?? '').toString(),
        body: (data['body'] ?? '').toString(),
        type: (data['type'] ?? 'general').toString(),
        referenceId: (data['referenceId'] ?? data['reference_id']) as String?,
      );
}
