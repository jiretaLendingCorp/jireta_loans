// lib/presentation/features/rider/location/providers/rider_location_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/location_remote_datasource.dart';

class RiderLocationState {
  final bool isTracking;
  final double? lastLat;
  final double? lastLng;
  final String? error;
  final DateTime? lastUpdated;

  const RiderLocationState({
    this.isTracking = false,
    this.lastLat,
    this.lastLng,
    this.error,
    this.lastUpdated,
  });

  RiderLocationState copyWith({
    bool? isTracking,
    double? lastLat,
    double? lastLng,
    String? error,
    DateTime? lastUpdated,
  }) =>
      RiderLocationState(
        isTracking: isTracking ?? this.isTracking,
        lastLat: lastLat ?? this.lastLat,
        lastLng: lastLng ?? this.lastLng,
        error: error,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
}

class RiderLocationNotifier extends StateNotifier<RiderLocationState> {
  final LocationRemoteDataSource _ds;
  Timer? _timer;

  RiderLocationNotifier(this._ds) : super(const RiderLocationState());

  void startTracking() {
    if (state.isTracking) return;
    state = state.copyWith(isTracking: true, error: null);
    _timer =
        Timer.periodic(const Duration(seconds: 30), (_) => _postLocation());
    _postLocation();
  }

  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(isTracking: false);
  }

  Future<void> _postLocation() async {
    try {
      await _ds.updateRiderLocation(
        lat: state.lastLat ?? 0.0,
        lng: state.lastLng ?? 0.0,
      );
      state = state.copyWith(lastUpdated: DateTime.now(), error: null);
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
    super.dispose();
  }
}

final riderLocationProvider =
    AutoDisposeStateNotifierProvider<RiderLocationNotifier, RiderLocationState>(
        (ref) {
  return RiderLocationNotifier(sl<LocationRemoteDataSource>());
});
