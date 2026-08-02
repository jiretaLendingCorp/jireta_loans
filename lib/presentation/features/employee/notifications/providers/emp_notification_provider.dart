// lib/presentation/features/employee/notifications/providers/emp_notification_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/notification_remote_datasource.dart';

final empNotificationProvider = StateNotifierProvider<EmpNotificationNotifier,
    AsyncValue<Map<String, dynamic>>>((ref) {
  return EmpNotificationNotifier(sl<NotificationRemoteDataSource>());
});

class EmpNotificationNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final NotificationRemoteDataSource _ds;
  EmpNotificationNotifier(this._ds)
      : super(const AsyncData({'items': [], 'total': 0}));

  Future<void> loadList({bool? isRead, int page = 1}) async {
    state = const AsyncLoading();
    try {
      final data = await _ds.getListMap(isRead: isRead, page: page);
      state = AsyncData(data);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<void> markRead({String? id}) async {
    try {
      await _ds.markRead(notificationId: id);
      await loadList();
    } catch (_) {}
  }
}
