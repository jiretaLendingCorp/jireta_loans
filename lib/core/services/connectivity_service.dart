// lib/core/services/connectivity_service.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../config/env_config.dart';

/// Thin wrapper around [Connectivity] plus a real reachability probe so
/// screens and providers can react to actual internet loss.
///
/// `connectivity_plus` only reports whether a network *interface* (Wi-Fi /
/// cellular) is up. A device connected to a router that lost its upstream link
/// still reports "online", so we additionally probe the Supabase endpoint to
/// confirm real internet access before declaring the app online.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  static const Duration _probeTimeout = Duration(seconds: 4);
  static const Duration _pollInterval = Duration(seconds: 5);

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

  /// True when the platform reports a network AND the Supabase endpoint is
  /// reachable. Failures (timeout, DNS, socket) are treated as offline.
  Future<bool> _probe() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (!_isOnline(results)) return false;
    } catch (_) {
      return false;
    }
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _probeTimeout,
        receiveTimeout: _probeTimeout,
      ));
      final response = await dio.get(
        '${EnvConfig.edgeFunctionsUrl}/',
        options: Options(
          // Never wait for a real body — any HTTP response proves the endpoint
          // (and therefore the internet) is up.
          validateStatus: (_) => true,
        ),
      );
      return response.statusCode != null;
    } catch (_) {
      return false;
    }
  }
}
