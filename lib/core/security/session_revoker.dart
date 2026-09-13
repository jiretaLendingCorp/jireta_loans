// lib/core/security/session_revoker.dart
import 'package:dio/dio.dart';

import '../config/env_config.dart';
import '../constants/app_constants.dart';
import '../network/api_endpoints.dart';
import '../utils/logger.dart';
import 'secure_storage.dart';

/// Best-effort revocation of THIS device's server-side active session.
///
/// The single-active-session rule is first-login-wins: the server's
/// `active_sessions` row stays "fresh" for ~5 minutes, so if it is not
/// revoked before the local session is torn down, the lender's NEXT login on
/// the same device is refused with "This account is already signed in on
/// another device."
///
/// Manual logout already posts `auth-logout` through the API client, but the
/// AUTO logout paths (10-minute idle expiry / dead refresh token) only cleared
/// local storage — leaving the stale row behind and blocking the immediate
/// re-login. This helper closes that gap and is safe to call from core
/// security code (own Dio, no auth interceptor, never throws).
class SessionRevoker {
  SessionRevoker._();

  static Future<void> revoke({String? sessionId}) async {
    String? sid = sessionId;
    if (sid == null || sid.isEmpty) {
      try {
        sid = await SecureStorage.getSessionId();
      } catch (_) {
        sid = null;
      }
    }
    if (sid == null || sid.isEmpty) return;

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: '${EnvConfig.edgeFunctionsUrl}/',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            // auth-logout only needs the anon key + the stable session id to
            // release the row, even when the access token is already expired.
            'apikey': EnvConfig.supabaseAnonKey,
            'Authorization': 'Bearer ${EnvConfig.supabaseAnonKey}',
            AppConstants.sessionIdHeaderName: sid,
          },
        ),
      );
      await dio.post(ApiEndpoints.authLogout, data: {'session_id': sid});
      AppLogger.debug('[Session] active session revoked for re-login');
    } catch (e) {
      AppLogger.debug('[Session] revoke failed (best effort): $e');
    }
  }
}
