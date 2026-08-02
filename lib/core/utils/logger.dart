// lib/core/utils/logger.dart
import 'package:flutter/foundation.dart';

class AppLogger {
  static void d(String message) {
    if (kDebugMode) debugPrint('[DEBUG] $message');
  }

  static void debug(String message) => d(message);

  static void i(String message) {
    if (kDebugMode) debugPrint('[INFO] $message');
  }

  static void info(String message) => i(message);

  static void w(String message) {
    if (kDebugMode) debugPrint('[WARN] $message');
  }

  static void warn(String message) => w(message);

  static void e(String message, [Object? error, StackTrace? st]) {
    if (kDebugMode) {
      debugPrint('[ERROR] $message');
      if (error != null) debugPrint('  Error: $error');
      if (st != null) debugPrint('  Stack: $st');
    }
  }

  static void error(String message, [Object? error, StackTrace? st]) =>
      e(message, error, st);
}
