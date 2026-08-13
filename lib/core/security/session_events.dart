// lib/core/security/session_events.dart
import 'dart:async';

/// Global broadcast channel that lets low-level layers (HTTP interceptors)
/// notify the UI that the user's session can no longer be repaired, so the
/// app can auto-logout instead of leaving a half-open session behind.
class SessionEvents {
  SessionEvents._();

  static final StreamController<void> _sessionExpired =
      StreamController<void>.broadcast();

  /// Fires whenever the stored tokens can never be refreshed again
  /// (invalid/expired refresh token, cleared session, etc).
  static Stream<void> get onSessionExpired => _sessionExpired.stream;

  static void emitSessionExpired() {
    if (!_sessionExpired.isClosed) _sessionExpired.add(null);
  }
}
