import 'package:dio/dio.dart';

import '../config/env_config.dart';
import '../constants/app_constants.dart';
import 'secure_storage.dart';

enum SessionRefreshResult { success, authRejected, offline }

class SessionRefresher {
  SessionRefresher._();

  static Future<SessionRefreshResult>? _inFlight;

  static Future<SessionRefreshResult> refresh() {
    final current = _inFlight;
    if (current != null) return current;

    final future = _refreshOnce();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }

  static Future<SessionRefreshResult> _refreshOnce() async {
    final refreshToken = await SecureStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return SessionRefreshResult.authRejected;
    }

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: '${EnvConfig.edgeFunctionsUrl}/',
          connectTimeout: const Duration(milliseconds: 10000),
          receiveTimeout: const Duration(milliseconds: 10000),
          sendTimeout: const Duration(milliseconds: 10000),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'apikey': EnvConfig.supabaseAnonKey,
            'Authorization': 'Bearer ${EnvConfig.supabaseAnonKey}',
          },
        ),
      );

      final response = await dio.post(
        AppConstants.authRefreshPath,
        data: {'refresh_token': refreshToken},
      );
      final data = response.data;
      if (data is! Map) return SessionRefreshResult.authRejected;

      final newAccessToken = data['access_token'];
      final newRefreshToken = data['refresh_token'];
      if (newAccessToken is! String || newAccessToken.isEmpty) {
        return SessionRefreshResult.authRejected;
      }

      await SecureStorage.saveTokens(
        accessToken: newAccessToken,
        refreshToken:
            newRefreshToken is String && newRefreshToken.isNotEmpty
                ? newRefreshToken
                : refreshToken,
      );
      return SessionRefreshResult.success;
    } on DioException catch (e) {
      if (e.response != null) return SessionRefreshResult.authRejected;
      return SessionRefreshResult.offline;
    } catch (_) {
      return SessionRefreshResult.authRejected;
    }
  }
}
