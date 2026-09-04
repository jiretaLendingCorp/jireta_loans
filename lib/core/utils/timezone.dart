// lib/core/utils/timezone.dart
library;

/// Centralized time utility for the app.
/// All timestamps in the system use Asia/Manila (UTC+8) timezone.

/// Asia/Manila is UTC+8
const int _manilaOffsetHours = 8;

/// Returns the current time in Asia/Manila timezone.
/// Use this instead of DateTime.now() throughout the app.
DateTime nowManila() {
  return DateTime.now().toUtc().add(const Duration(hours: _manilaOffsetHours));
}

/// Converts a UTC DateTime to Asia/Manila timezone.
/// If the input is already local, it's treated as UTC and converted.
DateTime toManila(DateTime utc) {
  if (utc.isUtc) {
    return utc.add(const Duration(hours: _manilaOffsetHours));
  }
  // If local, assume it was meant to be UTC
  return utc.toUtc().add(const Duration(hours: _manilaOffsetHours));
}

/// Formats a DateTime for display in Asia/Manila timezone.
/// Returns the DateTime adjusted to Manila time for formatting.
DateTime ensureManila(DateTime dt) {
  if (dt.isUtc) {
    return dt.add(const Duration(hours: _manilaOffsetHours));
  }
  return dt;
}

/// Parses a backend timestamp/date string into Asia/Manila wall time.
///
/// Values that carry a UTC/offset marker (real UTC from `DEFAULT NOW()` or
/// any ISO-8601 offset) represent an instant, so they are shifted +8h to
/// Manila. Pure dates ("2026-09-04") and already-local strings carry no
/// timezone marker and are returned unchanged.
///
/// NOTE: columns written via the `now_manila()` DB helper (e.g. `updated_at`
/// via `set_updated_at()`, `last_login_at`) store Manila wall time *as UTC*,
/// so they must NOT go through this helper — pass them through
/// `DateTime.tryParse` instead.
DateTime? parseManila(dynamic value) {
  if (value == null) return null;
  final dt = DateTime.tryParse(value.toString());
  if (dt == null) return null;
  return dt.isUtc ? dt.add(const Duration(hours: _manilaOffsetHours)) : dt;
}
