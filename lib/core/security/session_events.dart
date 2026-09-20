// lib/core/security/session_events.dart
import 'dart:async';

/// Server text for a single-active-session revocation. Kept here so the
/// interceptor, auth state and login screens all surface the same message.
const kSessionRevokedMessage =
    'Your account was signed in on another device. This session has been '
    'logged out for security.';

/// Reason kapag na-expire/nawala ang session pero WALANG ibang device na
/// gumamit ng account — (expired refresh token, o naabot ang idle limit).
/// Dapat hindi ito ipakita bilang "signed in on another device".
const kSessionExpiredMessage =
    'Your session has expired. Please sign in again.';

/// Kapag NATAPOS ang session dahil sa 10-minute idle limit para sa rider /
/// lender na may MPIN: hindi tuluyang nagla-log out ang app (naka-lock lang),
/// pero ipinapaalam pa rin sa user na kailangang mag-log in muli — gamit na
/// ngayon ang MPIN screen na may numero.
const kSessionEndedMessage =
    'Your session has ended. Please log in again.';

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
