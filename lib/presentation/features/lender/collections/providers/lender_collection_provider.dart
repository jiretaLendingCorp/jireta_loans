// lib/presentation/features/lender/collections/providers/lender_collection_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/network/dio_client.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../data/datasources/remote/location_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

final lenderCollectionProvider = AutoDisposeStateNotifierProvider<
    LenderCollectionNotifier, AsyncValue<Map<String, dynamic>>>((ref) {
  return LenderCollectionNotifier(
      sl<LocationRemoteDataSource>(), sl<DioClient>());
});

class LenderCollectionNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>>
    with RealtimeRefreshMixin {
  final LocationRemoteDataSource _locationDs;
  final DioClient _client;
  LenderCollectionNotifier(this._locationDs, this._client)
      : super(const AsyncData({'items': [], 'total': 0})) {
    bindRealtimeRefresh(['collection_assignments'], refresh: loadList);
    loadList();
  }

  Future<void> loadList({String? status, int page = 1}) async {
    state = const AsyncLoading();
    try {
      final res = await _client.get(
        ApiEndpoints.collectionsGetList,
        queryParams: {
          if (status != null) 'status': status,
          'page': page,
          'limit': 20,
        },
      );
      state = AsyncData(res.data as Map<String, dynamic>);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<Map<String, dynamic>> getDetail(String assignmentId) async {
    final res = await _client.get(
      '${ApiEndpoints.collectionsGetList}/$assignmentId',
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> getRiderLocation(String riderId) async {
    try {
      return await _locationDs.getRiderLocation(riderId: riderId);
    } catch (e) {
      return null;
    }
  }
}
