// lib/data/datasources/remote/location_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/tracked_rider_model.dart';

class LocationRemoteDataSource {
  final DioClient _client;
  LocationRemoteDataSource(this._client);

  Future<void> updateRiderLocation({
    required double lat,
    required double lng,
    double? speedKmh,
    double? accuracy,
  }) async {
    final payload = <String, dynamic>{'latitude': lat, 'longitude': lng};
    if (speedKmh != null && speedKmh.isFinite) {
      payload['speed_kmh'] = speedKmh;
      payload['speed'] = speedKmh / 3.6;
    }
    if (accuracy != null && accuracy.isFinite) payload['accuracy'] = accuracy;
    await _client.post(
      ApiEndpoints.locationUpdateRider,
      data: payload,
    );
  }

  Future<Map<String, dynamic>?> getRiderLocation({
    required String riderId,
  }) async {
    final res = await _client.get(
      ApiEndpoints.locationGetRider,
      queryParams: {'rider_id': riderId},
    );
    return res.data as Map<String, dynamic>?;
  }

  /// Returns every rider the lender may currently track live (accepted
  /// collection / CI, or in-flight rider-delivery disbursement on their loans),
  /// each merged with the rider's latest GPS fix.
  Future<List<TrackedRiderModel>> getTrackedRiders() async {
    final res = await _client.get(ApiEndpoints.locationListTracked);
    final body = res.data as Map<String, dynamic>;
    final items = body['riders'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(TrackedRiderModel.fromJson)
        .toList();
  }
}
