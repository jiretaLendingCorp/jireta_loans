// lib/core/services/connectivity_service.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../config/env_config.dart';

/// Thin wrapper around [Connectivity] plus a real reachability probe so
/// screens and providers can react to actual internet loss.
///
/// `connectivity_plus` only reports whether a network *interface* (Wi-Fi /
/// cellular) is up. A device connected to a router that lost its upstream link
/// still reports "online", so we additionally probe the Supabase endpoint to
/// confirm real internet access before declaring the app online.
///
/// REFACTORED for jireta.vercel.app (Aug 2026):
/// - On **web** `connectivity_plus` maps to `navigator.onLine` which is already
///   reliable. Performing a Dio GET to Supabase on web is *unreliable* because
///   a CORS mis-config (`CORS_ALLOWED_ORIGINS` missing the new origin) makes
///   the browser block the response — Dio then throws `DioExceptionType.unknown`
///   which the OLD code treated as "offline" → false "No Internet Connection"
///   even though the network is fine. On web we now trust the interface check
///   and skip the HTTP probe (or treat CORS/handshake failures as *online*).
/// - On **mobile** we keep the HTTP probe but:
///   * distinguish true offline (SocketException/timeout/dns) from server-side
///     mis-config (CORS/401/404/500 with a response) which should NOT mark offline,
///   * fall back to a public 204 endpoint (`connectivitycheck.gstatic.com`) when
///     the Supabase probe fails, so a temporarily-down Supabase doesn't fake offline,
///   * guard against the placeholder `your-project.supabase.co` used by vercel-build.sh
///     when Vercel env vars are missing.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  static const Duration _probeTimeout = Duration(seconds: 4);
  static const Duration _fallbackProbeTimeout = Duration(seconds: 3);
  static const Duration _pollInterval = Duration(seconds: 5);

  // Public, globally-reachable, CORS-friendly 204 used only as a *fallback*
  // when the Supabase probe fails — proves raw internet is up even if
  // Supabase is down or CORS-blocked.
  static const String _fallbackProbeUrl =
      'https://connectivitycheck.gstatic.com/generate_204';

  /// Emits the current online/offline status (true = real internet access)
  /// whenever it changes.
  ///
  /// Emits:
  ///   - immediately with the current status,
  ///   - whenever the network interface changes,
  ///   - every [_pollInterval] so a lost upstream link (Wi-Fi still "up")
  ///     is still detected without waiting for an interface event.
  Stream<bool> get onConnectionChanged {
    late StreamController<bool> controller;
    Timer? pollTimer;
    StreamSubscription<dynamic>? interfaceSub;
    var last = false;

    Future<void> emitProbe() async {
      final online = await _probe();
      if (!controller.isClosed && online != last) {
        last = online;
        controller.add(online);
      }
    }

    controller = StreamController<bool>(
      onListen: () {
        // Kick off the periodic reachability probe.
        emitProbe();
        pollTimer = Timer.periodic(_pollInterval, (_) => emitProbe());
        // React instantly to interface changes too.
        interfaceSub = _connectivity.onConnectivityChanged.listen((results) {
          if (!_isOnline(results)) {
            if (!controller.isClosed && last != false) {
              last = false;
              controller.add(false);
            }
          } else {
            emitProbe();
          }
        });
      },
      onCancel: () {
        pollTimer?.cancel();
        pollTimer = null;
        interfaceSub?.cancel();
        interfaceSub = null;
      },
    );

    return controller.stream;
  }

  /// One-shot check of the current status (real internet access).
  Future<bool> get isOnline => _probe();

  bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// True when the platform reports a network AND (on mobile) the internet is
  /// actually reachable. See class doc for web vs mobile behavior.
  Future<bool> _probe() async {
    // 1. Interface check — works on all platforms (on web: navigator.onLine).
    try {
      final results = await _connectivity.checkConnectivity();
      if (!_isOnline(results)) return false;
    } catch (_) {
      return false;
    }

    // 2. WEB fast-path: trust the interface. A Dio probe on web can be
    //    blocked by CORS (Access-Control-Allow-Origin: null when the new
    //    vercel origin isn't in CORS_ALLOWED_ORIGINS) and would incorrectly
    //    mark the app offline. If we reach here, navigator.onLine == true.
    if (kIsWeb) return true;

    // 3. MOBILE: probe the Supabase edge endpoint, with fallback.
    //    Guard against the placeholder used when Vercel env is missing — we
    //    don't want the app permanently stuck offline because of a build-time
    //    mis-config. Treat it as "can't verify via Supabase" → try fallback.
    final supabaseProbeUrl = EnvConfig.edgeFunctionsUrl;
    final isPlaceholder = supabaseProbeUrl.contains('your-project.supabase.co');

    if (!isPlaceholder) {
      final supabaseOnline = await _probeUrl(supabaseProbeUrl);
      if (supabaseOnline != null) return supabaseOnline;
      // null → inconclusive (timeout/socket) — try fallback before declaring offline
    }

    // 4. Fallback public probe — lightweight 204, CORS wildcard, proves raw internet.
    final fallbackOnline = await _probeUrl(
      _fallbackProbeUrl,
      timeout: _fallbackProbeTimeout,
    );
    if (fallbackOnline != null) return fallbackOnline;

    // Both probes inconclusive/failed → treat as offline.
    return false;
  }

  /// Probes [url] via Dio GET.
  ///
  /// Returns:
  /// - `true`  — got any HTTP response (status != null) → internet is up.
  ///             Even 401/404/500 proves the network + DNS worked; the server
  ///             just responded with an error. NOT offline.
  /// - `false` — explicit network failure (SocketException/host lookup/timeout).
  /// - `null`  — inconclusive transport error (e.g. CORS on web edge case) →
  ///             caller should try fallback instead of declaring offline.
  ///
  /// CORS/handshake failures on mobile are rare but if they occur we treat them
  /// as `true` (internet exists, server config is wrong) to avoid false offline.
  Future<bool?> _probeUrl(
    String url, {
    Duration? timeout,
  }) async {
    final t = timeout ?? _probeTimeout;
    Dio? dio;
    try {
      dio = Dio(BaseOptions(
        connectTimeout: t,
        receiveTimeout: t,
        sendTimeout: t,
      ));
      final response = await dio.get(
        url.endsWith('/') ? url : '$url/',
        options: Options(validateStatus: (_) => true),
      );
      return response.statusCode != null;
    } on DioException catch (e) {
      // Server actually responded (e.g. 401/403/500) → not offline.
      if (e.response?.statusCode != null) return true;

      final msg = e.message ?? '';
      final cause = e.error?.toString() ?? '';
      final combined = '$msg $cause'.toLowerCase();

      // True offline signals.
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return false;
      }
      if (e.type == DioExceptionType.connectionError) {
        // connectionError + SocketException/host lookup → offline.
        if (combined.contains('socketexception') ||
            combined.contains('failed host lookup') ||
            combined.contains('network is unreachable') ||
            combined.contains('connection refused') ||
            combined.contains('network is down')) {
          return false;
        }
        // On mobile a CORS failure shows as connectionError with ClientException
        // or "xmlhttprequest" on web — internet is up, config is wrong.
        if (combined.contains('xmlhttprequest') ||
            combined.contains('clientexception') ||
            combined.contains('handshakeexception')) {
          return true;
        }
        return false;
      }
      if (e.type == DioExceptionType.unknown) {
        if (combined.contains('socketexception') ||
            combined.contains('failed host lookup')) {
          return false;
        }
        if (combined.contains('handshakeexception') ||
            combined.contains('clientexception') ||
            combined.contains('xmlhttprequest') ||
            combined.contains('cors')) {
          return true;
        }
        // Other unknown transport errors → inconclusive, try fallback.
        return null;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      dio?.close(force: true);
    }
  }
}
