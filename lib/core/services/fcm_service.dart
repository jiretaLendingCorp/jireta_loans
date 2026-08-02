// lib/core/services/fcm_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/logger.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage msg) async {
  AppLogger.debug('[FCM] Background: ${msg.notification?.title}');
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  String? _token;
  String? get token => _token;

  Future<void> initialize() async {
    try {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );
      await _localNotifications.initialize(initSettings);

      _token = await _messaging.getToken();
      AppLogger.debug('[FCM] Token: $_token');

      _messaging.onTokenRefresh.listen((newToken) {
        _token = newToken;
        AppLogger.debug('[FCM] Token refreshed');
      });

      FirebaseMessaging.onMessage.listen(_handleForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedApp);
    } catch (e) {
      AppLogger.error('[FCM] Init failed: $e');
    }
  }

  void _handleForeground(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'jireta_channel',
          'Jireta Notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  void _handleOpenedApp(RemoteMessage message) {
    AppLogger.debug('[FCM] Opened from notification: ${message.data}');
  }
}
