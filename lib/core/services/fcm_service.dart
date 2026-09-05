// lib/core/services/fcm_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// FCM push channel for the EXISTING notification system.
//
// The in-app notification flow (notifications table → Supabase Realtime →
// Riverpod providers) is the SOURCE OF TRUTH and is untouched. This service
// only:
//   - requests notification permissions,
//   - retrieves the device FCM token (+ refresh) and registers it with the
//     device-tokens edge function (multi-device support),
//   - displays a local notification for FOREGROUND FCM messages (FCM does
//     not display them itself while the app is open),
//   - deep-links to the appropriate existing screen when a push is tapped
//     (background / terminated / foreground tap).
//
// Background/terminated pushes with a `notification` payload are displayed
// by the OS automatically — only a minimal isolate entry point is needed.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../../data/datasources/remote/device_token_remote_datasource.dart';
import '../constants/route_constants.dart';
import '../di/injection.dart';
import '../security/secure_storage.dart';
import '../utils/logger.dart';

/// Runs in its own isolate when the app is backgrounded/terminated.
/// Android/iOS automatically display pushes that carry a `notification`
/// payload, so nothing is required here beyond acknowledging the message.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage msg) async {
  AppLogger.debug('[FCM] Background: ${msg.notification?.title}');
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  // Lazily resolved: accessing FirebaseMessaging.instance before
  // Firebase.initializeApp() throws [core/no-app]. A getter (instead of a
  // field initializer) keeps mere construction of this singleton safe —
  // Firebase is only touched inside initialize()/syncWithUser(), which are
  // guarded by try/catch.
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _token;
  GoRouter? _router;
  RemoteMessage? _pendingInitialMessage;
  bool _initialized = false;

  /// Injected from app.dart so taps can navigate through the app's router
  /// (its redirects enforce auth + role, so deep links stay safe).
  void attachRouter(GoRouter router) {
    _router = router;
    // A cold-start tap may have arrived before the router existed.
    final pending = _pendingInitialMessage;
    if (pending != null) {
      _pendingInitialMessage = null;
      _navigateTo(pending.data);
    }
  }

  bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Wire up permission, token lifecycle and message handlers. Called once
  /// from main() after Firebase.initializeApp(). Safe to call on any
  /// platform — web/desktop become a no-op (web push is out of scope).
  Future<void> initialize() async {
    if (_initialized || !isSupportedPlatform) return;
    _initialized = true;

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // ── Local notification display channel (foreground messages) ──────
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: _handleLocalNotificationTap,
      );

      // ── Permission ─────────────────────────────────────────────────────
      // iOS/macOS: FirebaseMessaging.requestPermission() shows the prompt.
      // Android 13+: POST_NOTIFICATIONS runtime permission via the plugin.
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _localNotifications
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission();
        } catch (e) {
          AppLogger.error('[FCM] Android permission request failed: $e');
        }
      }

      // ── Token lifecycle ────────────────────────────────────────────────
      _token = await _messaging.getToken();
      if (_token != null) {
        AppLogger.debug('[FCM] Token acquired');
        await _registerToken(_token!);
      }

      _messaging.onTokenRefresh.listen((newToken) async {
        _token = newToken;
        AppLogger.debug('[FCM] Token refreshed');
        await _registerToken(newToken);
      });

      // ── Message handlers ───────────────────────────────────────────────
      // Foreground: FCM does not display the message itself → show a local
      // notification. The data payload carries the existing notification's
      // id so taps deep-link to the same screen as the in-app entry.
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // App opened from a notification (background → foreground, or
      // terminated → cold start after onBackgroundMessage).
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

      // Cold start from a terminated-state notification tap. Deferred until
      // the router is attached (app.dart) so navigation actually works.
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        if (_router == null) {
          _pendingInitialMessage = initial;
        } else {
          _handleOpenedMessage(initial);
        }
      }
    } catch (e) {
      AppLogger.error('[FCM] Init failed: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null || notification.title == null) return;

    final data = message.data;
    final notifId = (data['notification_id'] as String?) ?? '';
    // Stable id per notification row → the same push never stacks duplicates.
    final id = int.tryParse(notifId) ?? notifId.hashCode;

    _localNotifications.show(
      id,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'jireta_channel',
          'Jireta Notifications',
          channelDescription: 'Loan, payment, collection and assignment updates',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: _serializeTapPayload(data),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    AppLogger.debug('[FCM] Opened: ${message.data}');
    _navigateTo(message.data);
  }

  /// Foreground pushes are displayed as LOCAL notifications (FCM does not
  /// display them itself while the app is open); tapping one navigates too.
  void _handleLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final parts = payload.split('|');
    if (parts.length < 3) return;
    _navigateTo({
      'type': parts[0],
      'reference_id': parts[1],
      'notification_id': parts[2],
    });
  }

  // ── Token registration with the backend ──────────────────────────────────

  /// Registers the current (or freshly fetched) token for the logged-in
  /// user. Called after login and on token refresh.
  Future<void> syncWithUser() async {
    if (!isSupportedPlatform) return;
    try {
      final token = _token ?? await _messaging.getToken();
      if (token == null) return;
      _token = token;
      await _registerToken(token);
    } catch (e) {
      AppLogger.error('[FCM] syncWithUser failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    // Only register once a user session exists (device-tokens requires auth).
    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) return;
    try {
      await sl<DeviceTokenRemoteDataSource>().register(
        token: token,
        platform: _platformName,
      );
    } catch (e) {
      AppLogger.error('[FCM] Token registration failed: $e');
    }
  }

  /// Deactivates this device's token on logout so the user stops receiving
  /// pushes on this device.
  Future<void> unregister() async {
    if (!isSupportedPlatform || _token == null) return;
    try {
      await sl<DeviceTokenRemoteDataSource>().unregister(token: _token!);
    } catch (e) {
      AppLogger.error('[FCM] Token unregister failed: $e');
    }
  }

  String get _platformName {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'android';
    }
  }

  // ── Tap deep-linking ─────────────────────────────────────────────────────

  String _serializeTapPayload(Map<String, dynamic> data) {
    final type = (data['type'] ?? 'general').toString();
    final ref = (data['reference_id'] ?? '').toString();
    final notifId = (data['notification_id'] ?? '').toString();
    return '$type|$ref|$notifId';
  }

  /// Navigates to the existing screen that best matches the notification.
  /// Falls back to the role's notification center, which is exactly what the
  /// in-app UI does when a notification card is tapped.
  Future<void> _navigateTo(Map<String, dynamic> data) async {
    final router = _router;
    if (router == null) return;

    final type = (data['type'] ?? '').toString();
    final referenceId = (data['reference_id'] ?? '').toString();
    final role = await SecureStorage.getUserRole();

    final path = _routeFor(type: type, referenceId: referenceId, role: role);
    if (path != null && path.isNotEmpty) {
      router.go(path);
    }
  }

  String? _routeFor({
    required String type,
    required String referenceId,
    String? role,
  }) {
    String? detail(String base, {required bool needsRef}) {
      if (needsRef && (referenceId.isEmpty || referenceId == 'null')) return null;
      return referenceId.isEmpty || referenceId == 'null'
          ? null
          : base.replaceFirst(':id', referenceId);
    }

    switch (role) {
      case 'head_manager':
        return _routeForStaff(
          type: type,
          referenceId: referenceId,
          notifications: RouteConstants.hmNotifications,
          loan: RouteConstants.hmLoanDetails,
          ci: RouteConstants.hmCiDetails,
          collection: RouteConstants.hmCollectionDetails,
          payment: RouteConstants.hmPaymentDetails,
          disbursement: RouteConstants.hmDisbursementDetails,
          accountUpgrade: RouteConstants.hmAccountUpgradeDetails,
          detail: detail,
        );
      case 'employee':
        return _routeForStaff(
          type: type,
          referenceId: referenceId,
          notifications: RouteConstants.empNotifications,
          loan: RouteConstants.empLoanDetails,
          ci: RouteConstants.empCiDetails,
          collection: RouteConstants.empCollectionDetails,
          payment: RouteConstants.empPaymentDetails,
          disbursement: null, // employee has no disbursement details route
          accountUpgrade: RouteConstants.empAccountUpgradeDetails,
          detail: detail,
        );
      case 'rider':
        if (type.startsWith('ci_') || type == 'ci_required' || type == 'ci_overdue') {
          return detail(RouteConstants.riderCiDetails, needsRef: true);
        }
        if (type.startsWith('collection') ||
            type == 'collection_overdue' ||
            type == 'assignment_expired') {
          return detail(RouteConstants.riderCollectionDetails, needsRef: true);
        }
        if (type == 'disbursement' || type == 'disbursement_overdue') {
          return RouteConstants.riderDisbursements;
        }
        return RouteConstants.riderNotifications;
      case 'lender':
        if (type.startsWith('loan') ||
            type == 'penalty_applied' ||
            type == 'disbursement') {
          return detail(RouteConstants.lenderLoanDetails, needsRef: true);
        }
        if (type.startsWith('payment')) {
          return RouteConstants.lenderPaymentHistory;
        }
        if (type.startsWith('account_upgrade')) {
          return RouteConstants.lenderAccountUpgradeStatus;
        }
        if (type.startsWith('collection')) {
          return RouteConstants.lenderCollections;
        }
        return RouteConstants.lenderNotifications;
      default:
        return null;
    }
  }

  String? _routeForStaff({
    required String type,
    required String referenceId,
    required String notifications,
    required String? loan,
    required String? ci,
    required String? collection,
    required String? payment,
    required String? disbursement,
    required String? accountUpgrade,
    required String? Function(String base, {required bool needsRef}) detail,
  }) {
    final bool loanish = type.startsWith('loan') || type == 'penalty_applied';
    if (loanish && loan != null) {
      return detail(loan, needsRef: true);
    }
    if ((type.startsWith('ci_') || type == 'ci_required') && ci != null) {
      return detail(ci, needsRef: true);
    }
    if ((type.startsWith('collection') || type == 'assignment_expired') &&
        collection != null) {
      return detail(collection, needsRef: true);
    }
    if ((type.startsWith('payment')) && payment != null) {
      return detail(payment, needsRef: true);
    }
    if (type.startsWith('disbursement') && disbursement != null) {
      return detail(disbursement, needsRef: true);
    }
    if (type.startsWith('account_upgrade') && accountUpgrade != null) {
      return detail(accountUpgrade, needsRef: true);
    }
    return notifications;
  }
}