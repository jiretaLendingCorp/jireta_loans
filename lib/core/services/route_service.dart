// lib/core/services/route_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/env_config.dart';

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
    final key = EnvConfig.googleMapsApiKey.trim();
    if (key.isEmpty) return null;

    final routesApi = await _fetchRoutesApi(origin, destination, key);
    if (routesApi != null && routesApi.isNotEmpty) return routesApi;

    final legacy = await _fetchLegacyDirections(origin, destination, key);
    if (legacy != null && legacy.isNotEmpty) return legacy;

    return null;
  }

  /// Google Routes API (New): POST /directions/v2:computeRoutes.
  static Future<List<LatLng>?> _fetchRoutesApi(
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
        ..headers.set('X-Goog-Api-Key', key);
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
      return _decodePolyline(encoded);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Legacy Directions API: GET /maps/api/directions/json.
  static Future<List<LatLng>?> _fetchLegacyDirections(
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
      return _decodePolyline(encoded);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
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