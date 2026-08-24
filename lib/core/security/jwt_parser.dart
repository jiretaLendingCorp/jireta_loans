// lib/core/security/jwt_parser.dart
import 'dart:convert';

/// Minimal JWT payload decoder. Only reads claims; never verifies signatures.
class JwtParser {
  JwtParser._();

  /// Returns the decoded JWT payload map, or null if the token is malformed.
  static Map<String, dynamic>? decodePayload(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded);
      return map is Map<String, dynamic> ? map : null;
    } catch (_) {
      return null;
    }
  }

  /// Expiry claim (`exp`, seconds since epoch) as a UTC [DateTime], or null.
  static DateTime? expiry(String? token) {
    final exp = decodePayload(token)?['exp'];
    if (exp is int) {
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    }
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (exp * 1000).round(),
        isUtc: true,
      );
    }
    return null;
  }

  /// Issued-at claim (`iat`, seconds since epoch) as a UTC [DateTime], or null.
  static DateTime? issuedAt(String? token) {
    final iat = decodePayload(token)?['iat'];
    if (iat is int) {
      return DateTime.fromMillisecondsSinceEpoch(iat * 1000, isUtc: true);
    }
    if (iat is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (iat * 1000).round(),
        isUtc: true,
      );
    }
    return null;
  }

  /// Session start derived from JWT: prefers `iat`, falls back to `exp - 1h`,
  /// then to `now` if neither is available. Using server-issued iat/exp avoids
  /// client clock skew causing immediate "expired" after login on web.
  static DateTime sessionStartFromToken(String? token) {
    final iat = issuedAt(token);
    if (iat != null) return iat;
    final exp = expiry(token);
    if (exp != null) return exp.subtract(const Duration(hours: 1));
    return DateTime.now().toUtc();
  }

  /// True if the token is expired. Adds a small leeway (30s) to tolerate
  /// minor clock skew between client and Supabase server. If the token has no
  /// exp claim or is malformed, returns false so we don't incorrectly trigger
  /// a refresh loop — the server will be the source of truth and return 401
  /// if the token is truly invalid.
  static bool isExpired(String? token, {Duration leeway = const Duration(seconds: 30)}) {
    final exp = expiry(token);
    if (exp == null) return false;
    // Consider expired only if now is past exp + leeway (allows 30s skew).
    // For proactive refresh, callers should check `secondsUntilExpiry` < 30.
    return DateTime.now().toUtc().isAfter(exp.add(leeway));
  }

  /// True if the token will expire within [within] (default 60s). Used for
  /// proactive refresh before the token actually expires.
  static bool isExpiringSoon(String? token, {Duration within = const Duration(seconds: 60)}) {
    final secs = secondsUntilExpiry(token);
    if (secs == null) return false;
    return secs <= within.inSeconds;
  }

  /// Seconds until expiry (negative if already expired), null if malformed.
  static int? secondsUntilExpiry(String? token) {
    final exp = expiry(token);
    if (exp == null) return null;
    return exp.difference(DateTime.now().toUtc()).inSeconds;
  }
}
