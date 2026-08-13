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
    if (exp is int) return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch((exp * 1000).round());
    }
    return null;
  }
}
