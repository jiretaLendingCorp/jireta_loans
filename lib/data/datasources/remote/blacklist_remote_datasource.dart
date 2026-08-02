// lib/data/datasources/remote/blacklist_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';

class BlacklistRemoteDataSource {
  final DioClient _client;
  BlacklistRemoteDataSource(this._client);

  Future<Map<String, dynamic>> getBlacklist({
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.blacklistGetList,
      queryParams: {'page': page, 'limit': limit},
    );
    return _paged(res.data, page, limit);
  }

  Future<Map<String, dynamic>> getList({
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.blacklistGetList,
      queryParams: {
        if (search != null) 'search': search,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return {
      'items': list,
      'total': (res.data['total'] as num?)?.toInt() ?? list.length,
    };
  }

  Future<void> addToBlacklist({
    required String lenderId,
    required String reason,
  }) async {
    await _client.post(
      ApiEndpoints.blacklistAdd,
      data: {'lender_id': lenderId, 'reason': reason},
    );
  }

  Future<void> add({required String lenderId, required String reason}) =>
      addToBlacklist(lenderId: lenderId, reason: reason);

  Future<void> addBlacklist({
    required String lenderId,
    required String reason,
  }) =>
      addToBlacklist(lenderId: lenderId, reason: reason);

  Future<void> removeFromBlacklist({required String lenderId}) async {
    await _client.patch(
      ApiEndpoints.blacklistRemove,
      data: {'lender_id': lenderId},
    );
  }

  Future<void> remove({required String blacklistId}) =>
      removeFromBlacklist(lenderId: blacklistId);

  Future<void> removeBlacklist({required String lenderId}) =>
      removeFromBlacklist(lenderId: lenderId);

  Map<String, dynamic> _paged(Map<String, dynamic> body, int page, int limit) {
    final list = (body['data'] as List?) ?? [];
    final total = (body['total'] as num?)?.toInt() ?? list.length;
    final totalPages =
        (body['totalPages'] as num?)?.toInt() ??
        (limit == 0 ? 1 : (total / limit).ceil());
    return {
      'data': list,
      'meta': {'page': page, 'total_pages': totalPages, 'total': total},
    };
  }
}
