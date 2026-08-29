// lib/core/services/location_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../utils/logger.dart';

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  Timer? _timer;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  StreamSubscription<Position>? _positionStreamSub;
  bool _isTracking = false;
  Function(double lat, double lng)? _onLocationUpdate;
  Function(ServiceStatus status)? _onServiceStatusChanged;
  Function(LocationPermission permission)? _onPermissionChanged;

  /// Stream that emits immediately when the system location toggle is switched.
  /// Rider code can listen to detect GPS on/off without waiting for the next
  /// periodic fix (up to 30s delay before).
  Stream<ServiceStatus> get serviceStatusStream =>
      Geolocator.getServiceStatusStream();

  /// Current location-service enabled flag without requesting permission.
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Opens system location settings (Android) / privacy settings (iOS).
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Opens app-specific permission settings (when deniedForever).
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  /// Returns the current permission without triggering a system dialog.
  Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await requestPermission();
      if (!hasPermission) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      AppLogger.error('[Location] Error: $e');
      return null;
    }
  }

  void startTracking({
    required Duration interval,
    required Function(double lat, double lng) onUpdate,
    Function(ServiceStatus status)? onServiceStatusChanged,
    Function(LocationPermission permission)? onPermissionChanged,
  }) {
    if (_isTracking) return;
    _isTracking = true;
    _onLocationUpdate = onUpdate;
    _onServiceStatusChanged = onServiceStatusChanged;
    _onPermissionChanged = onPermissionChanged;

    // ── Immediate service-toggle detection (no polling delay) ───────
    _serviceStatusSub?.cancel();
    _serviceStatusSub =
        Geolocator.getServiceStatusStream().listen((status) async {
      AppLogger.debug('[Location] Service status changed: $status');
      _onServiceStatusChanged?.call(status);
      if (status == ServiceStatus.enabled) {
        // GPS just turned back on — fetch a fix immediately instead of waiting
        // for the next timer tick, so the live map dot jumps back on.
        final pos = await getCurrentPosition();
        if (pos != null) {
          _onLocationUpdate?.call(pos.latitude, pos.longitude);
        }
        // (Re)start the continuous position stream for sub-second movement.
        _startPositionStream();
      } else {
        // GPS off — stop the position stream to avoid error spam; timer
        // will keep trying and surface the GPS-off error in the provider.
        await _positionStreamSub?.cancel();
        _positionStreamSub = null;
      }
      // Also surface permission changes that may accompany the toggle.
      try {
        final perm = await Geolocator.checkPermission();
        _onPermissionChanged?.call(perm);
      } catch (_) {}
    });

    // ── Continuous high-accuracy position stream for smooth map anim ─
    _startPositionStream();

    // ── Fallback periodic timer (also covers devices where the position
    //    stream is throttled when app is backgrounded; guarantees a backend
    //    POST at least every [interval]).
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) async {
      final pos = await getCurrentPosition();
      if (pos != null) {
        _onLocationUpdate?.call(pos.latitude, pos.longitude);
      }
    });
    AppLogger.debug('[Location] Tracking started (stream + timer)');
  }

  void _startPositionStream() {
    _positionStreamSub?.cancel();
    try {
      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // emit on ~5m movement for smooth bearing anim
        ),
      ).listen(
        (pos) {
          _onLocationUpdate?.call(pos.latitude, pos.longitude);
        },
        onError: (e) {
          AppLogger.error('[Location] Position stream error: $e');
        },
      );
    } catch (e) {
      AppLogger.error('[Location] Failed to start position stream: $e');
    }
  }

  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    _serviceStatusSub?.cancel();
    _serviceStatusSub = null;
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
    _isTracking = false;
    _onLocationUpdate = null;
    _onServiceStatusChanged = null;
    _onPermissionChanged = null;
    AppLogger.debug('[Location] Tracking stopped');
  }

  bool get isTracking => _isTracking;
}
