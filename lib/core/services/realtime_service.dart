// lib/core/services/realtime_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../security/secure_storage.dart';
import '../utils/logger.dart';

/// Central hub for live database changes.
///
/// The app authenticates through custom Edge Functions (auth-login /
/// auth-verify-otp) and stores the returned JWT in SecureStorage, but it
/// never signs in the supabase_flutter client itself. Without a session the
/// Realtime socket connects with the anon key, `auth.uid()` is NULL, and RLS
/// filters out every event. Like [SupabaseStorageService], this restores the
/// session from the stored tokens before any channel is opened.
///
/// Each subscriber registers against a table; events on that table fire every
/// registered callback. A short per-table debounce collapses bursts of changes
/// (e.g. a loan insert that also touches schedules + notifications) into a
/// single refresh so we don't hammer the REST API.
class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  static const Duration _debounce = Duration(milliseconds: 400);

  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, List<void Function()>> _listeners = {};
  final Map<String, Timer> _debouncers = {};
  bool _sessionReady = false;

  /// Registers [onEvent] to fire whenever [table] changes. Safe to call
  /// multiple times for the same table + callback (deduplicated).
  Future<void> subscribe(String table, void Function() onEvent) async {
    final list = _listeners.putIfAbsent(table, () => []);
    if (!list.contains(onEvent)) list.add(onEvent);
    await _ensureSession();
    _openChannel(table);
  }

  /// Removes a previously registered [onEvent] for [table]. Closes the channel
  /// when the table has no remaining subscribers.
  void unsubscribe(String table, void Function() onEvent) {
    final list = _listeners[table];
    if (list == null) return;
    list.remove(onEvent);
    if (list.isEmpty) {
      _listeners.remove(table);
      _closeChannel(table);
    }
  }

  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) {
      _sessionReady = true;
      return;
    }
    final accessToken = await SecureStorage.getAccessToken();
    final refreshToken = await SecureStorage.getRefreshToken();
    if (accessToken == null || accessToken.isEmpty) {
      AppLogger.debug('[Realtime] No stored session to restore');
      return;
    }
    try {
      await client.auth.setSession(
        refreshToken ?? '',
        accessToken: accessToken,
      );
      _sessionReady = true;
    } catch (e) {
      AppLogger.error('[Realtime] Session restore failed: $e');
    }
  }

  void _openChannel(String table) {
    if (_channels.containsKey(table)) return;
    final channel = Supabase.instance.client.channel('postgres-$table');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (payload) => _onTableChanged(table),
        )
        .subscribe();
    _channels[table] = channel;
    AppLogger.debug('[Realtime] Subscribed to $table');
  }

  void _closeChannel(String table) {
    _debouncers[table]?.cancel();
    _debouncers.remove(table);
    _channels.remove(table)?.unsubscribe();
    AppLogger.debug('[Realtime] Unsubscribed from $table');
  }

  void _onTableChanged(String table) {
    _debouncers[table]?.cancel();
    _debouncers[table] = Timer(_debounce, () {
      for (final cb in List.of(_listeners[table] ?? const [])) {
        try {
          cb();
        } catch (e) {
          AppLogger.error('[Realtime] Listener error for $table: $e');
        }
      }
    });
  }

  /// Closes every channel (e.g. on logout) but keeps the registered listeners
  /// so the same providers reconnect automatically after the next login.
  Future<void> disconnect() async {
    for (final channel in _channels.values) {
      await channel.unsubscribe();
    }
    _channels.clear();
    for (final timer in _debouncers.values) {
      timer.cancel();
    }
    _debouncers.clear();
    _sessionReady = false;
  }

  /// Re-opens every channel with a freshly restored session. Call after login
  /// so the socket authenticates with the new user's JWT.
  Future<void> reconnect() async {
    await disconnect();
    await _ensureSession();
    for (final table in _listeners.keys.toList()) {
      _openChannel(table);
    }
  }
}
