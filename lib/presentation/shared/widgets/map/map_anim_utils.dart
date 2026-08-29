// lib/presentation/shared/widgets/map/map_anim_utils.dart
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Linear interpolation between two [LatLng] points.
/// Used to animate a marker smoothly from its previous GPS fix to the new one
/// instead of teleporting every ~30s.
LatLng lerpLatLng(LatLng a, LatLng b, double t) {
  final lat = a.latitude + (b.latitude - a.latitude) * t;
  final lng = a.longitude + (b.longitude - a.longitude) * t;
  return LatLng(lat, lng);
}

/// Bearing (heading) in degrees from [from] to [to], normalized to [0,360).
/// Useful to rotate a directional marker so it faces the direction of travel.
double bearingBetween(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLng = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  final brng = math.atan2(y, x) * 180 / math.pi;
  return (brng + 360) % 360;
}

/// Ease-in-out cubic curve approximation for marker motion.
/// Gives a natural accelerate → cruise → decelerate feel.
double easeInOutCubic(double t) {
  if (t < 0.5) return 4 * t * t * t;
  final f = (2 * t - 2);
  return 0.5 * f * f * f + 1;
}

/// Haversine distance in kilometers between two points.
double haversineKm(LatLng a, LatLng b) {
  const r = 6371.0; // earth radius km
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final sinDLat = math.sin(dLat / 2);
  final sinDLng = math.sin(dLng / 2);
  final h = sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLng * sinDLng;
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return r * c;
}

/// Total length of a polyline (road route) in km by summing Haversine segments.
double polylineKm(List<LatLng> points) {
  if (points.length < 2) return 0;
  var total = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    total += haversineKm(points[i], points[i + 1]);
  }
  return total;
}

/// Format distance: <1km as meters, otherwise 1 decimal km.
String formatDistanceKm(double km) {
  if (!km.isFinite || km < 0) return '--';
  if (km < 1) return '${(km * 1000).round()} m away';
  return '${km.toStringAsFixed(1)} km away';
}

/// Format GPS speed: validates, converts if needed elsewhere, handles display.
String formatSpeedKmh(double? kmh) {
  if (kmh == null || !kmh.isFinite || kmh < 0 || kmh > 120) return '--';
  if (kmh < 1) return '0 km/h';
  return '${kmh.toStringAsFixed(0)} km/h';
}

/// ETA from authoritative route duration (seconds from Directions/Routes API).
String formatEtaFromDuration(int durationSecs) {
  if (durationSecs <= 0) return 'Arriving';
  final mins = (durationSecs / 60).round();
  if (mins < 1) return '<1 min';
  if (mins == 1) return '1 min';
  return '$mins mins';
}

/// Estimate ETA mins from distance and speed (km/h).
/// If [speedKmh] is null/invalid, returns '--' instead of inventing value
/// unless [fallbackToEstimate] is true (uses 30 km/h avg for placeholder).
String formatEta(double km, {double? speedKmh, bool fallbackToEstimate = true}) {
  if (km <= 0) return 'Arriving';
  if (!km.isFinite) return '--';
  double? s = speedKmh;
  if (s == null || !s.isFinite || s <= 0 || s > 120) {
    if (!fallbackToEstimate) return '--';
    s = 30; // fallback only for display when no real speed yet
  }
  final mins = (km / s * 60).round();
  if (mins < 1) return '<1 min';
  if (mins == 1) return '1 min';
  return '$mins mins';
}

/// Combined helper: prefer API duration, else speed-based.
String formatEtaSmart({required double distanceKm, int? durationSecs, double? speedKmh}) {
  if (durationSecs != null && durationSecs > 0) return formatEtaFromDuration(durationSecs);
  return formatEta(distanceKm, speedKmh: speedKmh, fallbackToEstimate: true);
}
