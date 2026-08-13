// lib/presentation/shared/utils/error_suppression.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connectivity_provider.dart';

/// Returns true when the app is currently offline AND [message] looks like a
/// connection-level failure. Screens then suppress their own "No internet"
/// snackbars/dialogs and let the global ConnectivityOverlay toast be the only
/// offline indicator.
bool shouldSuppressNetworkError(BuildContext context, String message) {
  final m = message.toLowerCase();
  final isNetworkMessage = m.contains('no internet') ||
      m.contains('internet connection') ||
      m.contains('cannot connect') ||
      m.contains('unable to reach') ||
      m.contains('connection error') ||
      m.contains('connection refused') ||
      m.contains('network error') ||
      m.contains('timed out') ||
      m.contains('timeout') ||
      m.contains('socketexception') ||
      m.contains('failed host lookup') ||
      m.contains('secure connection failed') ||
      m.contains('server is not reachable') ||
      m.contains('dioexception');
  if (!isNetworkMessage) return false;

  try {
    final container = ProviderScope.containerOf(context, listen: false);
    final online = container.read(connectivityProvider).valueOrNull ?? true;
    return !online;
  } catch (_) {
    return false;
  }
}
