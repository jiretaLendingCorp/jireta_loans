// lib/core/security/session_events.dart
import 'dart:async';

/// Server text for a single-active-session revocation. Kept here so the
/// interceptor, auth state and login screens all surface the same message.
const kSessionRevokedMessage =
    'Your account was signed in on another device. This session has been '
    'logged out for security.';

/// Global broadcast channel that lets low-level layers (HTTP interceptors)
/// notify the UI that the user's session can no longer be repaired, so the
/// app can auto-logout instead of leaving a half-open session behind.
///
/// The event carries an optional [String] reason so the UI can explain WHY
/// the session ended (e.g. the single-active-session "signed in on another
/// device" message) instead of a generic "session expired".
class SessionEvents {
  SessionEvents._();

  static final StreamController<String?> _sessionExpired =
      StreamController<String?>.broadcast();

  /// Fires whenever the stored tokens can never be refreshed again
  /// (invalid/expired refresh token, cleared session, revoked by a newer
  /// login, etc). The emitted value is a human-readable reason when known.
  static Stream<String?> get onSessionExpired => _sessionExpired.stream;

  static void emitSessionExpired([String? reason]) {
    if (!_sessionExpired.isClosed) _sessionExpired.add(reason);
  }
}
