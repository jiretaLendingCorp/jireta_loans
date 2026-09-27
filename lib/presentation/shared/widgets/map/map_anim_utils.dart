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

// ── Destination (lender / borrower) pin ─────────────────────────────────────
//
// Ang destination pin ay LAGING galing sa naka-save na coordinates ng address
// record (`addresses.latitude/longitude`) na siyang ni-encode ng office — hindi
// sa client-side geocoding ng address text. Ang `locationFromAddress` ay
// walang web implementation (silent fail sa Chrome) at pwedeng mag-return ng
// maling barangay sa mobile, kaya dati ay walang lumalabas na destination
// marker / route / ETA kahit may address naman ang task.
class MapDestination {
  final double? lat;
  final double? lng;
  /// `street, barangay, city` — maikling label para sa marker info window.
  final String? label;
  /// `street, barangay, city, province` — buong address para sa card.
  final String? address;

  const MapDestination({this.lat, this.lng, this.label, this.address});

  bool get hasCoords => lat != null && lng != null;
  bool get isEmpty => lat == null && lng == null && address == null;
}

double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

Map<String, dynamic>? _asMap(dynamic v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), val))
    : (v is List && v.isNotEmpty ? _asMap(v.first) : null);

String? _joinParts(Map<String, dynamic> a, List<String> keys) {
  final parts = keys
      .map((k) => (a[k] ?? '').toString().trim())
      .where((p) => p.isNotEmpty && p != 'null')
      .toList();
  return parts.isEmpty ? null : parts.join(', ');
}

MapDestination _fromAddressRecord(Map<String, dynamic> a) => MapDestination(
      lat: _asDouble(a['latitude']),
      lng: _asDouble(a['longitude']),
      label: _joinParts(a, ['street', 'barangay', 'city']),
      address: _joinParts(a, ['street', 'barangay', 'city', 'province']),
    );

/// Reliable destination mula sa listahan ng address records (`lender_addresses`
/// sa collections, `addresses` sa loob ng loan payload).
///
/// Priority: unang record na MAY naka-save na lat/lng (para may pin na
/// maidodrowing), fallback sa primary/home record para sa text lang.
MapDestination destinationFromAddresses(List<dynamic>? addresses) {
  final maps = (addresses ?? const [])
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .toList();
  if (maps.isEmpty) return const MapDestination();

  Map<String, dynamic>? withCoords;
  for (final m in maps) {
    final d = _fromAddressRecord(m);
    if (d.hasCoords) {
      withCoords = m;
      break;
    }
  }
  final textOnly = maps.firstWhere(
    (m) => m['is_primary'] == true || m['address_type'] == 'home',
    orElse: () => maps.first,
  );
  return _fromAddressRecord(withCoords ?? textOnly);
}

/// Destination mula mismo sa loan payload — sinusuportahan ang embedded
/// `lender_profiles.users.addresses` (collections / disbursements / CI) at ang
/// flat `lender_address` snapshot (CI list) kapag wala ang embed.
MapDestination destinationFromLoan(Map<String, dynamic>? loan) {
  if (loan == null) return const MapDestination();
  for (final key in ['lender_profiles', 'lender_profile', 'lender']) {
    final profile = _asMap(loan[key]);
    if (profile == null) continue;
    final users = _asMap(profile['users']) ?? profile;
    final list = users['addresses'] ?? profile['addresses'];
    if (list is List && list.isNotEmpty) {
      final d = destinationFromAddresses(list);
      if (!d.isEmpty) return d;
    }
  }
  final flat = _asMap(loan['lender_address']) ?? _asMap(loan['address']);
  if (flat != null) return _fromAddressRecord(flat);
  return const MapDestination();
}
