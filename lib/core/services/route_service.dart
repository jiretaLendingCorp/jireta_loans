// lib/core/services/route_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/env_config.dart';

/// Structured result from [RouteService] so callers get the road geometry
/// **and** the authoritative distance/duration from the routing API.
///
/// Use [RouteResult.distanceKm] and [RouteResult.durationSecs] for ETA
/// instead of inventing a speed-based estimate when the API provides them.
class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationSecs;

  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationSecs,
  });
}

/// Fetches a real road route between two points so the map shows the actual
/// driving path (following roads, turns and intersections) instead of a
/// straight line between the rider and the destination.
///
/// Tries the modern Google Routes API first, then falls back to the legacy
/// Directions API, depending on which is enabled for the API key.
class RouteService {
  static Future<List<LatLng>?> fetchDrivingRoute(
    LatLng origin,
    LatLng destination,
  ) async {
    final result = await fetchRoute(origin, destination);
    return result?.points;
  }

  /// Returns road route with authoritative distance/duration.
  /// Falls back to null if no API key or no route.
  static Future<RouteResult?> fetchRoute(
    LatLng origin,
    LatLng destination,
  ) async {
    final key = EnvConfig.googleMapsApiKey.trim();
    if (key.isEmpty) return null;

    final routesApi = await _fetchRoutesApi(origin, destination, key);
    if (routesApi != null && routesApi.points.isNotEmpty) return routesApi;

    final legacy = await _fetchLegacyDirections(origin, destination, key);
    if (legacy != null && legacy.points.isNotEmpty) return legacy;

    return null;
  }

  /// Google Routes API (New): POST /directions/v2:computeRoutes.
  static Future<RouteResult?> _fetchRoutesApi(
    LatLng origin,
    LatLng destination,
    String key,
  ) async {
    final body = jsonEncode({
      'origin': {
        'location': {
          'latLng': {
            'latitude': origin.latitude,
            'longitude': origin.longitude,
          },
        },
      },
      'destination': {
        'location': {
          'latLng': {
            'latitude': destination.latitude,
            'longitude': destination.longitude,
          },
        },
      },
      'travelMode': 'DRIVE',
      'polylineEncoding': 'ENCODED_POLYLINE',
    });

    final client = HttpClient();
    try {
      final req = await client
          .postUrl(Uri.parse(
              'https://routes.googleapis.com/directions/v2:computeRoutes'))
        ..headers.contentType = ContentType.json
        ..headers.set('X-Goog-Api-Key', key)
        ..headers.set('X-Goog-FieldMask', 'routes.polyline.encodedPolyline,routes.duration,routes.distanceMeters');
      req.write(body);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final resBody = await res.transform(utf8.decoder).join();
      final data = jsonDecode(resBody) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final first = routes.first as Map<String, dynamic>;
      final polyline = first['polyline'] as Map<String, dynamic>?;
      final encoded = polyline?['encodedPolyline'] as String?;
      if (encoded == null || encoded.isEmpty) return null;
      final points = _decodePolyline(encoded);
      // Prefer API distance/duration; fallback to polyline haversine.
      final distMeters = (first['distanceMeters'] as num?)?.toDouble();
      final durationStr = first['duration'] as String?;
      double distKm = distMeters != null ? distMeters / 1000 : _polylineKm(points);
      int durSecs = 0;
      if (durationStr != null) {
        final m = RegExp(r'(\d+)').firstMatch(durationStr);
        if (m != null) durSecs = int.tryParse(m.group(1)!) ?? 0;
      }
      if (durSecs == 0 && distKm > 0) {
        // fallback estimate at 30 km/h if duration missing
        durSecs = (distKm / 30 * 3600).round();
      }
      return RouteResult(points: points, distanceKm: distKm, durationSecs: durSecs);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Legacy Directions API: GET /maps/api/directions/json.
  static Future<RouteResult?> _fetchLegacyDirections(
    LatLng origin,
    LatLng destination,
    String key,
  ) async {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json',
    ).replace(
      queryParameters: {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
        'key': key,
      },
    );

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final resBody = await res.transform(utf8.decoder).join();
      final data = jsonDecode(resBody) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final first = routes.first as Map<String, dynamic>;
      final polyline = first['overview_polyline'] as Map<String, dynamic>?;
      final encoded = polyline?['points'] as String?;
      if (encoded == null || encoded.isEmpty) return null;
      final points = _decodePolyline(encoded);
      // Try to get authoritative distance/duration from legs[0].
      double distKm = _polylineKm(points);
      int durSecs = 0;
      final legs = first['legs'] as List?;
      if (legs != null && legs.isNotEmpty) {
        final leg = legs.first as Map<String, dynamic>;
        final dist = leg['distance'] as Map<String, dynamic>?;
        final dur = leg['duration'] as Map<String, dynamic>?;
        if (dist != null && dist['value'] is num) {
          distKm = (dist['value'] as num).toDouble() / 1000;
        }
        if (dur != null && dur['value'] is num) {
          durSecs = (dur['value'] as num).toInt();
        }
      }
      if (durSecs == 0 && distKm > 0) {
        durSecs = (distKm / 30 * 3600).round();
      }
      return RouteResult(points: points, distanceKm: distKm, durationSecs: durSecs);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static double _polylineKm(List<LatLng> pts) {
    if (pts.length < 2) return 0;
    var total = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      total += _haversineKm(pts[i], pts[i + 1]);
    }
    return total;
  }

  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
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

  /// Decodes Google's Encoded Polyline Algorithm Format.
  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      var b = 0;
      var result = 0;
      var shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}