// lib/presentation/features/auth/providers/auth_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:gotrue/gotrue.dart' as gotrue;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../../core/services/realtime_service.dart';
import '../../../../data/datasources/remote/auth_remote_datasource.dart';
import '../../../../data/models/user_model.dart';
import '../../../shared/providers/auth_state_provider.dart';

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final AuthRemoteDataSource _ds;
  final AuthStateNotifier _authState;

  AuthNotifier(this._ds, this._authState) : super(const AsyncData(null));

  Future<bool> login({required String email, required String password}) async {
    state = const AsyncLoading();
    try {
      final res = await _ds.login(email: email, password: password);
      final token = res['access_token'] as String;
      final refresh = res['refresh_token'] as String;
      final userData = res['user'] as Map<String, dynamic>;
      await SecureStorage.saveTokens(accessToken: token, refreshToken: refresh);
      await SecureStorage.saveUserInfo(
        userId: userData['id'],
        role: userData['role'],
      );
      final user = UserModel(
        id: userData['id'],
        role: userData['role'],
        email: userData['email'],
        firstName: userData['first_name'] ?? '',
        lastName: userData['last_name'] ?? '',
        accountStatus: 'active',
        forcePasswordChange: userData['force_password_change'] ?? false,
        createdAt: DateTime.now(),
      );
      _authState.setAuthenticated(user);
      state = const AsyncData(null);
      RealtimeService.instance.reconnect();
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }

  Future<bool> sendOtp({required String phone}) async {
    state = const AsyncLoading();
    try {
      await _ds.sendOtp(phone: phone);
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }

  /// Google OAuth sign-in (mobile only).
  ///
  /// Opens the Google sign-in page in the system browser / secure web view.
  /// Google shows the account picker when several accounts exist and falls
  /// back to the "Enter your email" screen when none do. Once the user
  /// completes the flow, supabase_flutter restores the session via the deep
  /// link, and the exchange Edge Function maps it to a lender account
  /// (auto-creating one if the Google email is not registered yet).
  Future<bool> signInWithGoogle() async {
    state = const AsyncLoading();
    try {
      final session = await _performGoogleOAuth();
      if (session == null) {
        state = const AsyncData(null);
        return false;
      }
      final res = await _ds.googleExchange(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      final token = res['access_token'] as String;
      final refresh = res['refresh_token'] as String? ?? '';
      final userData = res['user'] as Map<String, dynamic>;
      await SecureStorage.saveTokens(accessToken: token, refreshToken: refresh);
      await SecureStorage.saveUserInfo(
        userId: userData['id'],
        role: userData['role'],
      );
      final user = UserModel(
        id: userData['id'],
        role: userData['role'],
        email: userData['email'],
        firstName: userData['first_name'] ?? '',
        lastName: userData['last_name'] ?? '',
        accountStatus: 'active',
        forcePasswordChange: userData['force_password_change'] ?? false,
        createdAt: DateTime.now(),
      );
      _authState.setAuthenticated(user);
      state = const AsyncData(null);
      RealtimeService.instance.reconnect();
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }

  /// Launches the browser OAuth flow and waits until supabase_flutter captures
  /// the session through the deep link. Returns null if the user cancels.
  Future<Session?> _performGoogleOAuth() async {
    final client = Supabase.instance.client;

    // Always start from a signed-out state. Reusing an existing session (e.g.
    // a phone-OTP login) would exchange the WRONG identity — its synthetic
    // `...@jireta.temp` email is not a Google account and the server rejects
    // the self-registration. A fresh flow guarantees the token below belongs
    // to the account the user just picked in the Google picker.
    try {
      await client.auth.signOut();
    } catch (e) {
      debugPrint('[auth] google OAuth pre-signout error: $e');
    }

    final completer = Completer<Session?>();
    final sub = client.auth.onAuthStateChange.listen((data) {
      // Only a freshly-completed sign-in counts. `initialSession` replays any
      // persisted session and a stale session's `tokenRefreshed` would hand us
      // the wrong identity — both are ignored so the exchange always uses the
      // Google session the user just authorized.
      if (!completer.isCompleted &&
          data.event == AuthChangeEvent.signedIn &&
          data.session != null) {
        completer.complete(data.session);
      }
    });

    try {
      await client.auth.signInWithOAuth(
        gotrue.OAuthProvider.google,
        redirectTo: AppConstants.googleOAuthRedirectUri,
        // Always show the Google account chooser (or the "enter your email"
        // screen) instead of auto-completing with the single already-authorized
        // account, so the user can pick which email to sign in with.
        queryParams: const {'prompt': 'select_account'},
      );
    } catch (e) {
      sub.cancel();
      debugPrint('[auth] google OAuth launch error: $e');
      rethrow;
    }

    try {
      return await completer.future.timeout(const Duration(minutes: 5));
    } catch (e) {
      // Timeout = the user never completed the browser flow.
      sub.cancel();
      debugPrint('[auth] google OAuth flow did not complete: $e');
      return null;
    }
  }

  Future<bool> verifyOtp({required String phone, required String otp}) async {
    state = const AsyncLoading();
    try {
      final res = await _ds.verifyOtp(phone: phone, otp: otp);
      final token = res['access_token'] as String;
      final refresh = res['refresh_token'] as String;
      final userData = res['user'] as Map<String, dynamic>;
      await SecureStorage.saveTokens(accessToken: token, refreshToken: refresh);
      await SecureStorage.saveUserInfo(
        userId: userData['id'],
        role: userData['role'],
      );
      final user = UserModel(
        id: userData['id'],
        role: userData['role'],
        phoneNumber: userData['phone_number'],
        firstName: userData['first_name'] ?? '',
        lastName: userData['last_name'] ?? '',
        accountStatus: 'active',
        forcePasswordChange: userData['force_password_change'] ?? false,
        createdAt: DateTime.now(),
      );
      _authState.setAuthenticated(user);
      state = const AsyncData(null);
      RealtimeService.instance.reconnect();
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }

  Future<bool> forceChangePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = const AsyncLoading();
    try {
      await _ds.forceChangePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _authState.setForcePasswordChangeDone();
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      // FIX: Log the REAL exception so a silent web failure (e.g. SecureStorage
      // throwing on web) isn't swallowed — the console previously stayed empty
      // while the snackbar showed a generic "can't reach" text.
      debugPrint('[auth] forceChangePassword error: $e');
      state = AsyncError(e, s);
      return false;
    }
  }

  Future<bool> forgotPassword({required String email}) async {
    state = const AsyncLoading();
    try {
      await _ds.forgotPassword(email: email);
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }

  Future<bool> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    state = const AsyncLoading();
    try {
      await _ds.resetPassword(token: token, newPassword: newPassword);
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }

  /// Best-effort server-side recording of the one-time Terms & Conditions
  /// acceptance. The local flag is the gate; the server record makes the
  /// acceptance durable per account (survives sign-out and device-data resets).
  Future<void> acceptTerms({
    required String deviceId,
    required String platform,
    required String appVersion,
  }) async {
    try {
      await _ds.acceptTerms(
        deviceId: deviceId,
        platform: platform,
        appVersion: appVersion,
      );
    } catch (_) {
      // Non-fatal: never block the user from proceeding past the terms screen.
    }
  }

  Future<void> logout() async {
    try {
      await _ds.logout();
    } catch (_) {}
    await RealtimeService.instance.disconnect();
    await _authState.logout();
    state = const AsyncData(null);
  }

  String? extractErrorMessage(Object error) {
    // Prefer the message ErrorInterceptor stores on DioException. It carries
    // the REAL server text (e.g. "Phone number not registered", "OTP login
    // not available for this role") or a friendly connection message. Using
    // DioException.toString() would embed the "DioException [type]:" prefix
    // and hide those details behind the generic fallback below.
    final isDio = error is DioException;
    final message = isDio && error.message?.isNotEmpty == true
        ? error.message!
        : error.toString();

    // FIX: Handle connection-level failures first so users see actionable text
    // instead of the raw DioException or "An error occurred" fallback.
    if (message.contains('NETWORK_ERROR') ||
        message.contains('Unable to reach server') ||
        message.contains('No internet')) {
      return 'Cannot connect to server. Check your internet connection and try again.';
    }
    if (message.contains('TIMEOUT') ||
        message.contains('timed out') ||
        message.contains('Request timed out')) {
      return 'Request timed out. Please try again.';
    }
    if (message.contains('Invalid email or password')) {
      return 'Invalid email or password.';
    }
    if (message.contains('Account locked')) {
      return 'Account locked. Try again later.';
    }
    if (message.contains('Account suspended')) {
      return 'Your account is suspended.';
    }
    if (message.contains('Rate limit') || message.contains('RATE_LIMITED')) {
      return 'Too many attempts. Please wait.';
    }
    if (message.contains('Invalid OTP code') ||
        message.contains('OTP expired or not found')) {
      return 'Invalid or expired OTP.';
    }
    // For Dio failures surface the server's actual message (so "Phone number
    // not registered" is no longer hidden behind the generic text). Only
    // non-Dio/local errors keep the generic fallback.
    return isDio ? message : 'An error occurred. Please try again.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<void>>((
  ref,
) {
  return AuthNotifier(
    sl<AuthRemoteDataSource>(),
    ref.watch(authStateProvider.notifier),
  );
});
