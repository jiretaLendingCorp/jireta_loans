// lib/core/services/location_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../utils/logger.dart';

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  Timer? _timer;
  bool _isTracking = false;
  Function(double lat, double lng)? _onLocationUpdate;

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
  }) {
    if (_isTracking) return;
    _isTracking = true;
    _onLocationUpdate = onUpdate;
    _timer = Timer.periodic(interval, (_) async {
      final pos = await getCurrentPosition();
      if (pos != null) {
        _onLocationUpdate?.call(pos.latitude, pos.longitude);
      }
    });
    AppLogger.debug('[Location] Tracking started');
  }

  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    _isTracking = false;
    _onLocationUpdate = null;
    AppLogger.debug('[Location] Tracking stopped');
  }

  bool get isTracking => _isTracking;
}
