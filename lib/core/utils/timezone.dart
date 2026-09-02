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
