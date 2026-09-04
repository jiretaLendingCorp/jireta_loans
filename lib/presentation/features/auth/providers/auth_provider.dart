// lib/presentation/features/auth/providers/auth_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:gotrue/gotrue.dart' as gotrue;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/security/jwt_parser.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../../core/services/realtime_service.dart';
import '../../../../core/utils/validators.dart';
import '../../../../data/datasources/remote/auth_remote_datasource.dart';
import '../../../../data/models/user_model.dart';
import '../../../shared/providers/auth_state_provider.dart';

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final AuthRemoteDataSource _ds;
  final AuthStateNotifier _authState;

  AuthNotifier(this._ds, this._authState) : super(const AsyncData(null));

  /// Pending Google OAuth completer, so the UI can cancel the browser flow
  /// (e.g. the user pressed back) instead of waiting for the full timeout.
  Completer<Session?>? _googleOAuthCompleter;

  /// Cancels a pending Google OAuth flow. Safe to call when no flow is in
  /// progress or the flow already completed.
  void cancelGoogleOAuth() {
    final completer = _googleOAuthCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _authState.startInteractiveAuth();
    state = const AsyncLoading();
    try {
      final res = await _ds.login(email: email, password: password);
      final token = res['access_token'] as String;
      final refresh = res['refresh_token'] as String;
      final userData = res['user'] as Map<String, dynamic>;
      // Ensure clean slate for second login (avoids race where old auto-logout's clearAll deletes new tokens)
      await SecureStorage.clearAll();
      await SecureStorage.saveTokens(accessToken: token, refreshToken: refresh);
      await SecureStorage.saveUserInfo(
        userId: userData['id'],
        role: userData['role'],
      );
      // ── 10-minute idle session: store login start time ─────────────────
      // Use JWT iat/exp (server time) instead of client now to avoid clock-skew
      // causing immediate "expired" on web when device clock is off.
      // saveSessionStartedAt also sets last_activity_at so idle window starts now.
      final sessionStart = JwtParser.sessionStartFromToken(token);
      await SecureStorage.saveSessionStartedAt(sessionStart);
      // Explicit bump to "now" so idle countdown is exactly 10m from this login
      await SecureStorage.saveLastActivity(DateTime.now().toUtc());
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

  Future<String?> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
    required String password,
    String? gender,
    String? civilStatus,
    required String otp,
  }) async {
    state = const AsyncLoading();
    try {
      await _ds.register(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phoneNumber: phoneNumber,
        password: password,
        gender: gender,
        civilStatus: civilStatus,
        otp: otp,
      );
      state = const AsyncData(null);
      return null;
    } catch (e, s) {
      state = AsyncError(e, s);
      return extractErrorMessage(e);
    }
  }

  Future<String?> sendRegisterOtp({
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    state = const AsyncLoading();
    try {
      await _ds.sendRegisterOtp(email: email, firstName: firstName, lastName: lastName);
      state = const AsyncData(null);
      return null;
    } catch (e, s) {
      state = AsyncError(e, s);
      return extractErrorMessage(e);
    }
  }

  Future<String?> verifyRegisterOtp({required String email, required String otp}) async {
    state = const AsyncLoading();
    try {
      await _ds.verifyRegisterOtp(email: email, otp: otp);
      state = const AsyncData(null);
      return null;
    } catch (e, s) {
      state = AsyncError(e, s);
      return extractErrorMessage(e);
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
    _authState.startInteractiveAuth();
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
      await SecureStorage.clearAll();
      await SecureStorage.saveTokens(accessToken: token, refreshToken: refresh);
      await SecureStorage.saveUserInfo(
        userId: userData['id'],
        role: userData['role'],
      );
      await SecureStorage.saveSessionStartedAt(JwtParser.sessionStartFromToken(token));
      await SecureStorage.saveLastActivity(DateTime.now().toUtc());
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
    _googleOAuthCompleter = completer;
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
      _googleOAuthCompleter = null;
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
    } finally {
      sub.cancel();
      if (identical(_googleOAuthCompleter, completer)) {
        _googleOAuthCompleter = null;
      }
    }
  }

  Future<bool> verifyOtp({required String phone, required String otp}) async {
    _authState.startInteractiveAuth();
    state = const AsyncLoading();
    try {
      final res = await _ds.verifyOtp(phone: phone, otp: otp);
      final token = res['access_token'] as String;
      final refresh = res['refresh_token'] as String;
      final userData = res['user'] as Map<String, dynamic>;
      await SecureStorage.clearAll();
      await SecureStorage.saveTokens(accessToken: token, refreshToken: refresh);
      await SecureStorage.saveUserInfo(
        userId: userData['id'],
        role: userData['role'],
      );
      await SecureStorage.saveSessionStartedAt(JwtParser.sessionStartFromToken(token));
      await SecureStorage.saveLastActivity(DateTime.now().toUtc());
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

  /// Extracts the lockout wait time from a 429 lockout error (OTP_LOCKED or
  /// ACCOUNT_LOCKED) so the UI can show a live countdown. Prefers the
  /// server-provided `retry_after_seconds`; falls back to parsing the message
  /// ("Try again in X minute(s)/second(s).") so the timer still works even when
  /// the deployed backend does not send the extra field yet.
  int? extractOtpLockoutSeconds(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final errObj = data['error'];
        if (errObj is Map) {
          final retry = errObj['retry_after_seconds'];
          if (retry is num) return retry.toInt();
          if (retry is String) return int.tryParse(retry);
        }
      }
      final fromMessage = _parseLockoutSecondsFromMessage(error.message ?? '');
      if (fromMessage != null) return fromMessage;
      final fromNested = error.error;
      if (fromNested is AppException) {
        final nested = _parseLockoutSecondsFromMessage(fromNested.message);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  /// "Try again in 3 minute(s)." / "in 15 minutes" / "in 45 seconds." →
  /// 180 / 900 / 45.
  int? _parseLockoutSecondsFromMessage(String message) {
    final minMatch = RegExp(
      r'in\s+(\d+)\s+minute',
      caseSensitive: false,
    ).firstMatch(message);
    if (minMatch != null) {
      return (int.tryParse(minMatch.group(1)!) ?? 1) * 60;
    }
    final secMatch = RegExp(
      r'in\s+(\d+)\s+second',
      caseSensitive: false,
    ).firstMatch(message);
    if (secMatch != null) return int.tryParse(secMatch.group(1)!);
    return null;
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

  /// Voluntary (self-service) password change. Unlike [forceChangePassword] it
  /// does NOT flip the local force-change flag — the user simply wants to
  /// rotate their password. Returns the server-side error message on failure
  /// so the UI can show exactly why (wrong current password, weak password,
  /// password reuse, network error, etc.).
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = const AsyncLoading();
    try {
      await _ds.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      state = const AsyncData(null);
      return null;
    } catch (e, s) {
      debugPrint('[auth] changePassword error: $e');
      state = AsyncError(e, s);
      return extractErrorMessage(e);
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

  Future<bool> verifyResetOtp({required String email, required String otp}) async {
    state = const AsyncLoading();
    try {
      await _ds.verifyResetOtp(email: email, otp: otp);
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }

  Future<bool> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    state = const AsyncLoading();
    try {
      await _ds.resetPassword(email: email, otp: otp, newPassword: newPassword);
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }

  // Legacy token-based reset kept for old links (not used by OTP flow)
  Future<bool> resetPasswordWithToken({
    required String token,
    required String newPassword,
  }) async {
    state = const AsyncLoading();
    try {
      await _ds.resetPasswordWithToken(token: token, newPassword: newPassword);
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
    // Expose loading via AsyncValue so any watcher can react to
    // authProvider.isLoading. The pressed logout button itself shows the
    // spinner — no full-screen "Logging out" modal is used.
    state = const AsyncLoading();
    try {
      try {
        await _ds.logout();
      } catch (_) {}
      // SECURITY: also destroy the local supabase session (used by realtime,
      // storage, and Google OAuth). Without this the client-side session
      // survives logout and can still access RLS-protected resources.
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      await RealtimeService.instance.disconnect();
      await _authState.logout();
    } finally {
      state = const AsyncData(null);
    }
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
    // Preserve CORS/DNS hints — don't blanket-hide them behind generic text.
    if (message.contains('CORS') ||
        message.contains('DNS failed') ||
        message.contains('CORS_ALLOWED_ORIGINS') ||
        message.contains('jireta.vercel.app')) {
      return message; // surface the detailed hint from ErrorInterceptor
    }
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
    if (message.contains('Wrong username or password')) {
      // Backend message already includes remaining attempts
      // (e.g. "Wrong username or password. 2 attempts left.").
      return message;
    }
    if (message.contains('Account locked')) {
      return 'Account locked. Try again later.';
    }
    if (message.contains('OTP_LOCKED') ||
        message.contains('Too many wrong OTP attempts')) {
      return 'Too many wrong attempts. Please wait before trying again.';
    }
    if (message.contains('Account suspended')) {
      return 'Your account is suspended.';
    }
    if (message.contains('Account pending approval')) {
      return 'Account pending approval. Please wait for the head manager to approve your account.';
    }
    if (message.contains('LOGIN_RATE_LIMITED') ||
        message.contains('Too many login attempts')) {
      return 'Too many login attempts. Try again in a few minutes.';
    }
    if (message.contains('OTP_RATE_LIMITED') ||
        message.contains('Too many OTP')) {
      return 'Too many OTP requests. Please wait before trying again.';
    }
    if (message.contains('PASSWORD_RESET_RATE_LIMITED') ||
        message.contains('Too many reset requests')) {
      return 'Too many reset requests. Please try again later.';
    }
    if (message.contains('PAYMENT_ATTEMPT_BLOCKED') ||
        message.contains('Too many payment attempts')) {
      return 'Payment attempt temporarily blocked for review. Please try again later.';
    }
    if (message.contains('Rate limit') || message.contains('RATE_LIMITED')) {
      return 'Too many attempts. Please wait.';
    }
    if (message.contains('Invalid OTP code') ||
        message.contains('OTP expired or not found')) {
      return 'Invalid or expired OTP.';
    }
    if (message.contains('INVALID_TOKEN') ||
        message.contains('Invalid or expired reset token')) {
      return 'Reset link is invalid or has expired. Please request a new one.';
    }
    if (message.contains('PASSWORD_REUSE') ||
        message.contains('Cannot reuse last')) {
      return 'Cannot reuse any of your last 5 passwords. Please choose a different password.';
    }
    if (message.contains('Password must contain') ||
        message.contains('Password must be at least')) {
      return message; // surface backend validation as-is
    }
    // ── Email Uniqueness Check (security) ─────────────────────────────
    // Surface duplicate-email/phone violations with a clear, field-specific
    // message instead of the raw Postgres / GoTrue text.  The helper is
    // case-insensitive and covers both the Edge Function 409 ("Email already
    // registered") and a raw unique-index violation ("duplicate key …
    // uq_users_email_lower").
    // Try to extract the typed code from Dio's response payload as well.
    String? duoCode;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final errObj = data['error'];
        if (errObj is Map) duoCode = errObj['code']?.toString();
        duoCode ??= data['code']?.toString();
      }
      final inner = error.error;
      if (duoCode == null && inner is AppException) duoCode = inner.code;
    }
    if (AppValidators.isEmailDuplicateError(message, duoCode)) {
      return AppValidators.duplicateEmailMessage;
    }
    // Phone duplicate sibling — same DUPLICATE code but different field.
    if (message.toLowerCase().contains('phone') &&
        (message.toLowerCase().contains('already') ||
            message.toLowerCase().contains('duplicate') ||
            duoCode?.toUpperCase() == 'DUPLICATE')) {
      // Distinguish the exact text so the user knows which field collided.
      if (message.toLowerCase().contains('phone')) {
        return 'Phone number already registered. Please use a different number.';
      }
    }
    if (duoCode?.toUpperCase() == 'DUPLICATE' ||
        message.contains('DUPLICATE')) {
      // Generic duplicate fallback for any other unique violation.
      return message;
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
