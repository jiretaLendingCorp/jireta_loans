// lib/presentation/features/rider/location/providers/rider_location_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/security/secure_storage.dart';
import '../../../../../core/services/location_service.dart';
import '../../../../../data/datasources/remote/location_remote_datasource.dart';

class RiderLocationState {
  final bool isTracking;
  final double? lastLat;
  final double? lastLng;
  final double? lastSpeedKmh;
  final String? error;
  final DateTime? lastUpdated;

  const RiderLocationState({
    this.isTracking = false,
    this.lastLat,
    this.lastLng,
    this.lastSpeedKmh,
    this.error,
    this.lastUpdated,
  });

  RiderLocationState copyWith({
    bool? isTracking,
    double? lastLat,
    double? lastLng,
    Object? lastSpeedKmh = _sentinel,
    Object? error = _sentinel,
    DateTime? lastUpdated,
  }) {
    return RiderLocationState(
      isTracking: isTracking ?? this.isTracking,
      lastLat: lastLat ?? this.lastLat,
      lastLng: lastLng ?? this.lastLng,
      lastSpeedKmh: identical(lastSpeedKmh, _sentinel)
          ? this.lastSpeedKmh
          : lastSpeedKmh as double?,
      error: identical(error, _sentinel) ? this.error : error as String?,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  static const _sentinel = Object();
}

class RiderLocationNotifier extends StateNotifier<RiderLocationState> {
  final LocationRemoteDataSource _ds;
  Timer? _timer;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  StreamSubscription<Position>? _positionSub;
  final List<double> _speedHistory = [];

  RiderLocationNotifier(this._ds) : super(const RiderLocationState());

  void startTracking() {
    if (state.isTracking) return;
    state = state.copyWith(isTracking: true, error: null);

    // ── Instant GPS toggle detection ───────────────────────────────
    // Geolocator.getServiceStatusStream() fires the moment the user flips
    // the system location switch, so we surface the GPS-off / GPS-on state
    // immediately instead of waiting up to 30s for the next timer tick.
    _serviceStatusSub?.cancel();
    _serviceStatusSub =
        Geolocator.getServiceStatusStream().listen((status) async {
      final enabled = status == ServiceStatus.enabled;
      if (!mounted) return;
      if (!enabled) {
        state = state.copyWith(
            error: 'GPS is off. Please turn on location services.');
        if (kDebugMode) debugPrint('[RiderLocation] Service disabled');
        // Stop the position stream while GPS is off to avoid error spam.
        await _positionSub?.cancel();
        _positionSub = null;
      } else {
        // GPS just turned back on — clear error and fetch a fix immediately
        // so the live map dot reappears without delay.
        state = state.copyWith(error: null);
        if (kDebugMode) debugPrint('[RiderLocation] Service enabled — re-acquiring');
        _startPositionStream();
        await _postLocation();
      }
    });

    // ── Continuous position stream for smooth bearing / speed ──────
    _startPositionStream();

    // ── Periodic backend POST (timer) ──────────────────────────────
    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(seconds: 30), (_) => _postLocation());
    _postLocation();
    // Prime the service-status error so the banner shows instantly if GPS
    // is already off when the rider opens the tracking screen.
    _refreshServiceError();
  }

  void _startPositionStream() {
    _positionSub?.cancel();
    try {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (pos) => _handleStreamPosition(pos),
        onError: (e) async {
          if (kDebugMode) debugPrint('[RiderLocation] stream error: $e');
          await _refreshServiceError();
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[RiderLocation] start stream failed: $e');
    }
  }

  Future<void> _handleStreamPosition(Position pos) async {
    if (!mounted) return;
    // Validate permission/role before posting
    try {
      final role = await SecureStorage.getUserRole();
      if (role != AppConstants.roleRider) {
        stopTracking();
        return;
      }
    } catch (_) {
      stopTracking();
      return;
    }
    await _processAndPostPosition(pos);
  }

  Future<void> _refreshServiceError() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (state.error == null || !state.error!.contains('GPS is off')) {
          state = state.copyWith(
              error: 'GPS is off. Please turn on location services.');
        }
        return;
      }
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.deniedForever) {
        state = state.copyWith(
            error:
                'Location permission permanently denied. Please enable it in app settings.');
      } else if (perm == LocationPermission.denied) {
        state = state.copyWith(
            error:
                'Location permission denied. Please enable location permission for the app.');
      } else {
        // Service on + permission granted → clear any GPS/permission error
        if (state.error != null &&
            (state.error!.contains('GPS is off') ||
                state.error!.contains('permission'))) {
          state = state.copyWith(error: null);
        }
      }
    } catch (_) {}
  }

  /// Call when app resumes (WidgetsBindingObserver.didChangeAppLifecycleState)
  /// so a permission/GPS change made while the app was backgrounded is
  /// detected instantly when the rider returns.
  Future<void> onAppResumed() async {
    if (!state.isTracking) return;
    await _refreshServiceError();
    // If GPS is back on, trigger an immediate fix
    final enabled = await Geolocator.isLocationServiceEnabled().catchError((_) => false);
    if (enabled) {
      await _postLocation();
      _startPositionStream();
    }
  }

  /// Opens system location settings (GPS toggle screen).
  Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {}
  }

  /// Opens app permission settings (when deniedForever).
  Future<void> openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }

  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    _serviceStatusSub?.cancel();
    _serviceStatusSub = null;
    _positionSub?.cancel();
    _positionSub = null;
    if (mounted) state = state.copyWith(isTracking: false);
  }

  Future<void> _processAndPostPosition(Position pos) async {
    try {
      // Validate and convert GPS speed: m/s -> km/h (3.6).
      double? rawSpeedKmh;
      final rawSpeedMs = pos.speed;
      final speedAcc = pos.speedAccuracy;
      final isSpeedValid = rawSpeedMs.isFinite &&
          rawSpeedMs >= 0 &&
          rawSpeedMs < 70 &&
          speedAcc.isFinite &&
          speedAcc >= 0 &&
          speedAcc < 20;
      if (isSpeedValid) {
        rawSpeedKmh = rawSpeedMs * 3.6;
        if (rawSpeedKmh > 120) rawSpeedKmh = null;
      }
      double? smoothedKmh;
      if (rawSpeedKmh != null) {
        _speedHistory.add(rawSpeedKmh);
        if (_speedHistory.length > 5) _speedHistory.removeAt(0);
        final sum = _speedHistory.reduce((a, b) => a + b);
        smoothedKmh = sum / _speedHistory.length;
      } else {
        if (_speedHistory.isNotEmpty) {
          final sum = _speedHistory.reduce((a, b) => a + b);
          smoothedKmh = sum / _speedHistory.length;
          if (_speedHistory.length > 3) _speedHistory.removeAt(0);
        } else {
          smoothedKmh = null;
        }
        if (rawSpeedMs == 0 && smoothedKmh != null && smoothedKmh < 2) {
          smoothedKmh = 0;
        }
      }
      try {
        await _ds.updateRiderLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          speedKmh: smoothedKmh,
          accuracy: pos.accuracy,
        );
      } catch (_) {
        await _ds.updateRiderLocation(lat: pos.latitude, lng: pos.longitude);
      }
      state = state.copyWith(
        lastLat: pos.latitude,
        lastLng: pos.longitude,
        lastSpeedKmh: smoothedKmh,
        lastUpdated: DateTime.now(),
        error: null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Location stream post failed: $e');
      state = state.copyWith(error: ErrorHandler.handle(e).message);
    }
  }

  Future<void> _postLocation() async {
    // The backend rejects `update-rider` with a 403 unless the caller is a
    // rider. Guard against the tracking timer firing after logout / a role
    // switch on the same device (the provider outlives the session), so a
    // lender/employee session never POSTs a rider location.
    try {
      final role = await SecureStorage.getUserRole();
      if (role != AppConstants.roleRider) {
        stopTracking();
        return;
      }
    } catch (_) {
      stopTracking();
      return;
    }

    try {
      final pos = await LocationService.instance.getCurrentPosition();
      if (pos == null) {
        // Distinguish between GPS-off vs permission denied for the banner text
        bool serviceEnabled = false;
        LocationPermission perm = LocationPermission.denied;
        try {
          serviceEnabled = await Geolocator.isLocationServiceEnabled();
          perm = await Geolocator.checkPermission();
        } catch (_) {}
        String msg;
        if (!serviceEnabled) {
          msg = 'GPS is off. Please turn on location services.';
        } else if (perm == LocationPermission.deniedForever) {
          msg =
              'Location permission permanently denied. Please enable it in app settings.';
        } else {
          msg =
              'Location permission denied. Please enable location permission for the app.';
        }
        state = state.copyWith(error: msg);
        if (kDebugMode) debugPrint('[RiderLocation] $msg');
        return;
      }
      // Validate and convert GPS speed: m/s -> km/h (3.6).
      // Handle invalid: speed <0, speedAccuracy unavailable/high, or NaN.
      double? rawSpeedKmh;
      final rawSpeedMs = pos.speed;
      final speedAcc = pos.speedAccuracy;
      final isSpeedValid = rawSpeedMs.isFinite &&
          rawSpeedMs >= 0 &&
          rawSpeedMs < 70 && // ~252 km/h max sanity
          speedAcc.isFinite &&
          speedAcc >= 0 &&
          speedAcc < 20; // high inaccuracy -> unreliable
      if (isSpeedValid) {
        rawSpeedKmh = rawSpeedMs * 3.6;
        // Clamp absurd jumps; moving average will smooth.
        if (rawSpeedKmh > 120) rawSpeedKmh = null;
      }
      double? smoothedKmh;
      if (rawSpeedKmh != null) {
        _speedHistory.add(rawSpeedKmh);
        if (_speedHistory.length > 5) _speedHistory.removeAt(0);
        final sum = _speedHistory.reduce((a, b) => a + b);
        smoothedKmh = sum / _speedHistory.length;
      } else {
        // No valid speed fix: keep decay but don't feed bad value.
        // If we have history, reuse last smoothed; else null -> UI shows --.
        if (_speedHistory.isNotEmpty) {
          final sum = _speedHistory.reduce((a, b) => a + b);
          smoothedKmh = sum / _speedHistory.length;
          // Decay slowly if GPS keeps failing: drop oldest after 3 fails
          if (_speedHistory.length > 3) _speedHistory.removeAt(0);
        } else {
          smoothedKmh = null;
        }
        // If speed shows 0 while moving below threshold, treat as stopped
        if (rawSpeedMs == 0 && smoothedKmh != null && smoothedKmh < 2) {
          smoothedKmh = 0;
        }
      }
      // Send to backend: include speed (km/h) and accuracy for lender display.
      try {
        await _ds.updateRiderLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          speedKmh: smoothedKmh,
          accuracy: pos.accuracy,
        );
      } catch (_) {
        // Still update local state even if backend fails
        await _ds.updateRiderLocation(lat: pos.latitude, lng: pos.longitude);
      }
      state = state.copyWith(
        lastLat: pos.latitude,
        lastLng: pos.longitude,
        lastSpeedKmh: smoothedKmh,
        lastUpdated: DateTime.now(),
        error: null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Location update failed: $e');
      state = state.copyWith(error: ErrorHandler.handle(e).message);
    }
  }

  void updateCoordinates(double lat, double lng) {
    state = state.copyWith(lastLat: lat, lastLng: lng);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _serviceStatusSub?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }
}

final riderLocationProvider =
    StateNotifierProvider<RiderLocationNotifier, RiderLocationState>((ref) {
  return RiderLocationNotifier(sl<LocationRemoteDataSource>());
});
