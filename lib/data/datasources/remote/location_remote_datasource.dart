// lib/data/datasources/remote/location_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';

class LocationRemoteDataSource {
  final DioClient _client;
  LocationRemoteDataSource(this._client);

  Future<void> updateRiderLocation({
    required double lat,
    required double lng,
  }) async {
    await _client.post(
      ApiEndpoints.locationUpdateRider,
      data: {'lat': lat, 'lng': lng},
    );
  }

  Future<Map<String, dynamic>?> getRiderLocation({
    required String riderId,
  }) async {
    try {
      final res = await _client.get(
        ApiEndpoints.locationGetRider,
        queryParams: {'rider_id': riderId},
      );
      return res.data as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}
