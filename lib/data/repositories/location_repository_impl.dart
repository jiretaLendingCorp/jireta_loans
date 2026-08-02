// lib/data/repositories/location_repository_impl.dart
import '../../domain/repositories/i_location_repository.dart';
import '../datasources/remote/location_remote_datasource.dart';

class LocationRepositoryImpl implements ILocationRepository {
  final LocationRemoteDataSource _ds;
  LocationRepositoryImpl(this._ds);

  @override
  Future<void> updateRiderLocation(double lat, double lng) =>
      _ds.updateRiderLocation(lat: lat, lng: lng);

  @override
  Future<Map<String, dynamic>?> getRiderLocation(String riderId) =>
      _ds.getRiderLocation(riderId: riderId);
}
