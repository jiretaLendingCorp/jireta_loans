// lib/presentation/shared/providers/auth_state_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/role_constants.dart';
import '../../../core/security/jwt_parser.dart';
import '../../../core/security/session_events.dart';
import '../../../core/security/session_refresher.dart';
import '../../../core/security/secure_storage.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/utils/logger.dart';
import '../../../data/models/user_model.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final UserModel? user;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.error,
  });

  String? get role => user?.role;
  bool get forcePasswordChange => user?.forcePasswordChange ?? false;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserModel? user,
    String? error,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isLoading: isLoading ?? this.isLoading,
        user: user ?? this.user,
        error: error,
      );
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  AuthStateNotifier() : super(const AuthState()) {
    _sessionExpiredSub = SessionEvents.onSessionExpired.listen((_) async {
      await _onSessionExpired();
    });
  }

  StreamSubscription<void>? _sessionExpiredSub;
  Timer? _expiryTimer;
  bool _isRefreshing = false;
  int _authRevision = 0;

  @override
  void dispose() {
    _sessionExpiredSub?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> initialize() async {
    final revision = _authRevision;
    state = state.copyWith(isLoading: true);
    try {
      // ── 1-hour absolute session check ──────────────────────────────────
      // hasValidSession now checks both token existence AND absolute expiry.
      final hasSession = await SecureStorage.hasValidSession();
      if (revision != _authRevision || !mounted) return;
      if (hasSession) {
        final userId = await SecureStorage.getUserId();
        final role = await SecureStorage.getUserRole();
        if (revision != _authRevision || !mounted) return;
        if (userId != null &&
            role != null &&
            RoleConstants.allRoles.contains(role)) {
          // ── Absolute 1-hour check before auto-login ────────────────────
          // Use same 30s grace as SecureStorage.isAbsoluteSessionExpired to avoid
          // false logout due to clock skew or timer precision right after login.
          final remaining = await SecureStorage.getRemainingSessionTime();
          if (remaining != null && remaining.inSeconds <= -30) {
            if (kDebugMode) debugPrint('[JWT] initialize: absolute session expired (1h) → hard logout, require re-login');
            AppLogger.debug('[JWT] initialize: absolute 1h expired → clear for re-login');
            await SecureStorage.clearAll();
            try {
              await Supabase.instance.client.auth.signOut();
            } catch (_) {}
            if (revision != _authRevision || !mounted) return;
            state = const AuthState(isAuthenticated: false);
            return;
          }

          // Legacy migration: if no startedAt but token exists, infer from JWT
          if (remaining == null) {
            final accessToken = await SecureStorage.getAccessToken();
            final exp = JwtParser.expiry(accessToken);
            if (exp != null) {
              // Infer startedAt = exp - 1h (JWT lifetime)
              final inferredStart = exp.subtract(AppConstants.sessionDuration);
              final now = DateTime.now().toUtc();
              // Only migrate if JWT still has time left; otherwise treat as expired
              if (now.isBefore(exp)) {
                await SecureStorage.saveSessionStartedAt(inferredStart);
                if (kDebugMode) debugPrint('[JWT] initialize: migrated legacy session startedAt=$inferredStart exp=$exp');
              } else {
                // JWT already expired and no absolute timestamp → try soft refresh
                // within absolute window not possible, so treat as expired if JWT also expired
                // Attempt one soft refresh before logout to handle clock skew
                if (kDebugMode) debugPrint('[JWT] initialize: legacy JWT expired, trying soft refresh');
                AppLogger.debug('[JWT] initialize: legacy JWT expired, pre-refresh');
                final preResult = await _tryRefreshSession();
                if (revision != _authRevision || !mounted) return;
                if (preResult == SessionRefreshResult.authRejected) {
                  await SecureStorage.clearAll();
                  try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
                  if (revision != _authRevision || !mounted) return;
                  state = const AuthState(isAuthenticated: false);
                  return;
                } else if (preResult == SessionRefreshResult.success) {
                  // After successful refresh we now have fresh JWT, set new absolute start
                  await SecureStorage.saveSessionStartedAt(DateTime.now().toUtc());
                } else {
                  // offline → keep session, timer will retry
                }
              }
            }
          } else {
            // Absolute still valid but JWT may be soft-expired (e.g. reopened tab after 59m)
            // Try soft refresh to keep JWT valid until absolute expiry, without extending absolute.
            final accessToken = await SecureStorage.getAccessToken();
            if (JwtParser.isExpired(accessToken) || JwtParser.isExpiringSoon(accessToken, within: const Duration(seconds: 60))) {
              // Only soft-refresh if absolute still has meaningful time (>30s to avoid last-second churn)
              if (remaining.inSeconds > 30) {
                if (kDebugMode) debugPrint('[JWT] initialize: JWT soft-expired but absolute valid (${remaining.inSeconds}s left) → soft refresh');
                AppLogger.debug('[JWT] initialize: soft JWT expired, pre-refresh');
                final preResult = await _tryRefreshSession();
                if (revision != _authRevision || !mounted) return;
                switch (preResult) {
                  case SessionRefreshResult.authRejected:
                    if (kDebugMode) debugPrint('[JWT] initialize: soft refresh rejected → hard logout');
                    AppLogger.debug('[JWT] initialize: soft refresh rejected → clear');
                    await SecureStorage.clearAll();
                    try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
                    if (revision != _authRevision || !mounted) return;
                    state = const AuthState(isAuthenticated: false);
                    return;
                  case SessionRefreshResult.offline:
                    if (kDebugMode) debugPrint('[JWT] initialize: offline during soft refresh, keep session');
                    break;
                  case SessionRefreshResult.success:
                    if (kDebugMode) debugPrint('[JWT] initialize: soft refresh success, continue');
                    break;
                }
              } else {
                // Absolute is about to expire anyway (<10s) → hard expire shortly
                if (kDebugMode) debugPrint('[JWT] initialize: JWT expired and absolute almost expired (${remaining.inSeconds}s) → will hard logout');
              }
            }
          }

          state = AuthState(
            isAuthenticated: true,
            user: UserModel(
              id: userId,
              role: role,
              firstName: '',
              lastName: '',
              accountStatus: 'active',
              forcePasswordChange: false,
              createdAt: DateTime.now(),
            ),
          );
          // Schedule hard 1h expiry (or soft JWT refresh if JWT sooner)
          _scheduleExpiryCheck();
          return;
        }
      }
      if (revision != _authRevision || !mounted) return;
      state = const AuthState(isAuthenticated: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[JWT] initialize error: $e');
      if (revision != _authRevision || !mounted) return;
      state = const AuthState(isAuthenticated: false);
    } finally {
      if (revision == _authRevision && mounted && state.isLoading) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  void startInteractiveAuth() {
    _authRevision++;
    _expiryTimer?.cancel();
    if (state.isLoading) {
      state = state.copyWith(isLoading: false);
    }
  }

  void setAuthenticated(UserModel user) {
    _authRevision++;
    _expiryTimer?.cancel();
    state = AuthState(isAuthenticated: true, user: user);
    _scheduleExpiryCheck();
  }

  void setForcePasswordChangeDone() {
    if (state.user != null) {
      state = state.copyWith(
        user: state.user!.copyWith(forcePasswordChange: false),
      );
    }
  }

  Future<void> logout() async {
    _authRevision++;
    _expiryTimer?.cancel();
    _isRefreshing = false;
    try {
      await RealtimeService.instance.disconnect();
    } catch (_) {}
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await SecureStorage.clearAll();
    if (mounted) {
      state = const AuthState(isAuthenticated: false);
    } else {
      state = const AuthState(isAuthenticated: false);
    }
    AppLogger.debug('[JWT] logout complete → will redirect to login (re-login enabled)');
    if (kDebugMode) debugPrint('[AuthState] logout: session cleared, ready for re-login');
  }

  /// Schedules hard logout at absolute 1-hour expiry.
  /// Within the 1-hour window, if JWT soft-expires before absolute, we do a
  /// soft refresh that does NOT extend the absolute 1h deadline.
  void _scheduleExpiryCheck() {
    _expiryTimer?.cancel();
    _checkTokenExpiry();
  }

  Future<void> _checkTokenExpiry() async {
    try {
      final remaining = await SecureStorage.getRemainingSessionTime();
      final accessToken = await SecureStorage.getAccessToken();
      final jwtExp = JwtParser.expiry(accessToken);
      final now = DateTime.now().toUtc();

      // ── Case 1: No absolute timestamp (legacy) → fallback to JWT ────────
      if (remaining == null) {
        if (jwtExp == null) {
          if (kDebugMode) debugPrint('[JWT] no absolute & no exp claim → skip timer (legacy, wait for user action)');
          return;
        }
        final delay = jwtExp.difference(now) - const Duration(seconds: 4);
        if (kDebugMode) debugPrint('[JWT] legacy fallback: exp=$jwtExp now=$now delay=${delay.inSeconds}s → ${delay.isNegative ? "already expired" : "schedule soft timer"}');
        AppLogger.debug('[JWT] legacy JWT exp=$jwtExp delay=${delay.inSeconds}s');
        if (!delay.isNegative) {
          _expiryTimer = Timer(delay, _onSoftTokenExpired);
          if (kDebugMode) debugPrint('[JWT] legacy soft timer scheduled for ${delay.inSeconds}s');
        } else {
          _onSoftTokenExpired();
        }
        return;
      }

      // ── Case 2: Absolute session already expired → hard logout ─────────
      // 30s grace prevents immediate logout due to clock skew right after login.
      if (remaining.inSeconds <= -30) {
        if (kDebugMode) debugPrint('[JWT] absolute 1h expired → hard logout immediately');
        AppLogger.debug('[JWT] absolute 1h expired, hard logout');
        _onAbsoluteSessionExpired();
        return;
      }

      final absoluteExpiry = now.add(remaining);
      if (kDebugMode) debugPrint('[JWT] absolute remaining=${remaining.inSeconds}s expiry=$absoluteExpiry');

      // ── Case 3: Absolute valid, check JWT soft expiry ──────────────────
      if (jwtExp != null) {
        final jwtRemaining = jwtExp.difference(now);
        final jwtDelay = jwtRemaining - const Duration(seconds: 4);
        if (kDebugMode) debugPrint('[JWT] jwtExp=$jwtExp jwtRemaining=${jwtRemaining.inSeconds}s jwtDelay=${jwtDelay.inSeconds}s absoluteRemaining=${remaining.inSeconds}s');

        // JWT soft-expired but absolute still has time → soft refresh (no extension of absolute)
        if (jwtDelay.isNegative) {
          if (remaining.inSeconds > 10) {
            if (kDebugMode) debugPrint('[JWT] JWT soft-expired but absolute valid (${remaining.inSeconds}s left) → soft refresh now');
            _onSoftTokenExpired();
          } else {
            // Absolute about to expire (<10s) → just wait for hard expiry
            if (kDebugMode) debugPrint('[JWT] JWT expired and absolute almost done (${remaining.inSeconds}s) → schedule hard logout');
            _expiryTimer = Timer(remaining, _onAbsoluteSessionExpired);
          }
          return;
        }

        // Both valid: schedule timer for whichever comes first
        // Optimization: if JWT soft expiry is within 10s of hard expiry, skip soft refresh and go straight to hard logout
        // (avoids wasteful refresh 4s before the 1h hard logout)
        final Duration nextDelay;
        final bool isJwtSooner;
        if (jwtDelay < remaining) {
          final gap = remaining - jwtDelay;
          if (gap.inSeconds <= 10 || remaining.inSeconds < 60) {
            // Too close to hard expiry — just schedule hard logout
            nextDelay = remaining;
            isJwtSooner = false;
          } else {
            nextDelay = jwtDelay;
            isJwtSooner = true;
          }
        } else {
          nextDelay = remaining;
          isJwtSooner = false;
        }

        if (kDebugMode) debugPrint('[JWT] next timer in ${nextDelay.inSeconds}s → ${isJwtSooner ? "soft JWT refresh" : "hard 1h logout"}');
        AppLogger.debug('[JWT] schedule next in ${nextDelay.inSeconds}s isJwtSooner=$isJwtSooner');

        if (isJwtSooner) {
          _expiryTimer = Timer(nextDelay, _onSoftTokenExpired);
        } else {
          _expiryTimer = Timer(nextDelay, _onAbsoluteSessionExpired);
        }
      } else {
        // No JWT exp claim → just schedule hard absolute expiry
        if (kDebugMode) debugPrint('[JWT] no JWT exp, schedule hard absolute in ${remaining.inSeconds}s');
        _expiryTimer = Timer(remaining, _onAbsoluteSessionExpired);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[JWT] _checkTokenExpiry error: $e');
    }
  }

  /// Hard 1-hour expiry: session MUST end, require re-login, new 1h starts.
  Future<void> _onAbsoluteSessionExpired() async {
    if (kDebugMode) debugPrint('[JWT] absolute 1h session expired → hard logout, require re-login');
    AppLogger.debug('[JWT] absolute 1h expired → hard logout');
    // No refresh — 1 hour is absolute. User must login again to get new 1h.
    await _onSessionExpired();
  }

  /// Soft JWT expiry within the 1h window: try refresh WITHOUT extending absolute 1h.
  Future<void> _onSoftTokenExpired() async {
    // If absolute already expired (with grace), hard logout instead of soft refresh
    final remaining = await SecureStorage.getRemainingSessionTime();
    if (remaining != null && remaining.inSeconds <= -30) {
      if (kDebugMode) debugPrint('[JWT] _onSoftTokenExpired but absolute already expired → hard logout');
      await _onAbsoluteSessionExpired();
      return;
    }

    if (_isRefreshing) {
      if (kDebugMode) debugPrint('[JWT] _onSoftTokenExpired skipped (already refreshing)');
      return;
    }
    _isRefreshing = true;
    if (kDebugMode) debugPrint('[JWT] JWT soft expired → attempting soft refresh (absolute ${remaining?.inSeconds}s left)...');
    AppLogger.debug('[JWT] soft JWT expired, attempting refresh within 1h window');
    try {
      final result = await _tryRefreshSession();
      if (!mounted) return;
      switch (result) {
        case SessionRefreshResult.success:
          if (kDebugMode) debugPrint('[JWT] soft refresh success → reschedule (absolute still governs)');
          AppLogger.debug('[JWT] soft refresh success, reschedule');
          // New JWT stored but absolute NOT extended → next timer still targets absolute expiry
          // Also need to ensure startedAt still preserved; saveTokens does not touch startedAt
          _scheduleExpiryCheck();
          break;
        case SessionRefreshResult.authRejected:
          if (kDebugMode) debugPrint('[JWT] soft refresh rejected → hard logout');
          AppLogger.debug('[JWT] soft refresh rejected → hard logout');
          await _onSessionExpired();
          break;
        case SessionRefreshResult.offline:
          if (kDebugMode) debugPrint('[JWT] offline during soft refresh → retry 30s, keep session until hard expiry');
          AppLogger.debug('[JWT] offline soft refresh, keep session, retry 30s');
          if (mounted) {
            _expiryTimer?.cancel();
            _expiryTimer = Timer(const Duration(seconds: 30), _onSoftTokenExpired);
          }
          break;
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// One-shot token refresh used by the expiry scheduler. Kept independent of
  /// [AuthInterceptor] so expired-token detection works even while the app is
  /// idle and no request is being made.
  Future<SessionRefreshResult> _tryRefreshSession() => SessionRefresher.refresh();

  Future<void> _onSessionExpired() async {
    if (!state.isAuthenticated) {
      if (kDebugMode) debugPrint('[JWT] _onSessionExpired ignored (already logged out)');
      return;
    }
    // ── Stale event guard for multiple logins ───────────────────────────
    // If a sessionExpired event was emitted for an OLD session (e.g. first
    // login's 1h timer) but the user has already logged in again (second
    // login) and the new session is still valid, ignore the stale event.
    // This fixes "second login expired immediately".
    final remaining = await SecureStorage.getRemainingSessionTime();
    if (remaining != null && remaining.inSeconds > 10) {
      // New session still has >10s left → stale event, don't logout.
      if (kDebugMode) debugPrint('[JWT] _onSessionExpired ignored stale event, remaining ${remaining.inSeconds}s (second login still valid)');
      AppLogger.debug('[JWT] ignore stale sessionExpired, remaining ${remaining.inSeconds}s');
      return;
    }
    // Also check hasValidSession for legacy (no startedAt) – don't ignore if truly expired
    final hasSession = await SecureStorage.hasValidSession();
    if (remaining == null && hasSession) {
      // Legacy: no absolute timestamp, check JWT instead – if JWT still valid, stale
      final token = await SecureStorage.getAccessToken();
      if (token != null && !JwtParser.isExpired(token)) {
        if (kDebugMode) debugPrint('[JWT] _onSessionExpired ignored stale legacy event, JWT still valid');
        return;
      }
    }
    if (kDebugMode) debugPrint('[JWT] session expired → auto-logout + clear storage → allow re-login');
    AppLogger.debug('[JWT] session expired → auto-logout');
    _expiryTimer?.cancel();
    await logout();
    // Emit is already done by the caller (AuthInterceptor); but if the timer
    // path triggered this, we need to ensure the stream fires for any other listeners.
    // (No double-emit harm – broadcast stream deduplicates via state check).
  }
}

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
  ref,
) {
  return AuthStateNotifier()..initialize();
});
