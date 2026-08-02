// lib/domain/repositories/i_location_repository.dart
abstract class ILocationRepository {
  Future<void> updateRiderLocation(double lat, double lng);
  Future<Map<String, dynamic>?> getRiderLocation(String riderId);
}
