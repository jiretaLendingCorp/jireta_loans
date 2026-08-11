// lib/core/services/connectivity_service.dart
import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin wrapper around [Connectivity] so screens and providers can react to
/// network loss without depending on the plugin API directly.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  /// Emits the current online/offline status whenever it changes.
  Stream<bool> get onConnectionChanged =>
      _connectivity.onConnectivityChanged.map(_isOnline);

  /// One-shot check of the current network status.
  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return _isOnline(results);
  }

  bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any(
      (r) => r != ConnectivityResult.none,
    );
  }
}
