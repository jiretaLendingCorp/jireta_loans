// lib/data/datasources/remote/user_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/user_model.dart';

class UserRemoteDataSource {
  final DioClient _client;
  UserRemoteDataSource(this._client);

  Future<Map<String, dynamic>> createEmployee(Map<String, dynamic> data) async {
    final res = await _client.post(
      ApiEndpoints.usersCreateEmployee,
      data: data,
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createRider(Map<String, dynamic> data) async {
    final res = await _client.post(ApiEndpoints.usersCreateRider, data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createLender(Map<String, dynamic> data) async {
    final res = await _client.post(ApiEndpoints.usersCreateLender, data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<UserModel> getProfile({String? userId}) async {
    final res = await _client.get(
      ApiEndpoints.usersGetProfile,
      queryParams: userId != null ? {'user_id': userId} : null,
    );
    final data = (res.data as Map<String, dynamic>)['user'];
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getProfileMap({String? userId}) async {
    final res = await _client.get(
      ApiEndpoints.usersGetProfile,
      queryParams: userId != null ? {'user_id': userId} : null,
    );
    final data = (res.data as Map<String, dynamic>)['user'];
    return data as Map<String, dynamic>;
  }

  Future<List<UserModel>> getUsers({
    String? role,
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    final res = await _client.get(
      ApiEndpoints.usersGetList,
      queryParams: {
        if (role != null) 'role': role,
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
        if (search != null) 'search': search,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    await _client.patch(ApiEndpoints.usersUpdateProfile, data: data);
  }

  Future<void> archive(String userId) async {
    await _client.patch(ApiEndpoints.usersArchive, data: {'user_id': userId});
  }

  /// Restore an archived user — sets account_status back to 'active'.
  /// Requirement: "KAPAG NA UNARCHIVED NA THEN MA RERESTORE NA UNG ACCOUNT
  /// MAGAGAMIT NA NI USER" — archived = blocked, unarchived = usable again.
  Future<void> unarchive(String userId) async {
    await _client.patch(ApiEndpoints.usersUnarchive, data: {'user_id': userId});
  }

  // Alias for restore (used by Archived screen)
  Future<void> restore(String userId) => unarchive(userId);

  // ── Role archiving — archived role = ALL users with that role blocked ──
  Future<void> archiveRole(String roleName) async {
    await _client.patch(ApiEndpoints.rolesArchive, data: {'role': roleName});
  }

  Future<void> unarchiveRole(String roleName) async {
    await _client.patch(ApiEndpoints.rolesUnarchive, data: {'role': roleName});
  }

  Future<void> restoreRole(String roleName) => unarchiveRole(roleName);

  Future<List<Map<String, dynamic>>> getRoles() async {
    final res = await _client.get(ApiEndpoints.rolesGetList);
    final list = (res.data['roles'] as List?) ?? (res.data['data'] as List?) ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getList({
    String? role,
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    final res = await _client.get(
      ApiEndpoints.usersGetList,
      queryParams: {
        if (role != null) 'role': role,
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
        if (search != null) 'search': search,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return {
      'items': list,
      'total': (res.data['total'] as num?)?.toInt() ?? list.length,
    };
  }

  Future<Map<String, dynamic>> getUserList({
    String? role,
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    final res = await _client.get(
      ApiEndpoints.usersGetList,
      queryParams: {
        if (role != null) 'role': role,
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
        if (search != null) 'search': search,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    final total = (res.data['total'] as num?)?.toInt() ?? list.length;
    final totalPages = (res.data['totalPages'] as num?)?.toInt() ??
        (limit == 0 ? 1 : (total / limit).ceil());
    return {
      'data': list,
      'meta': {'page': page, 'total_pages': totalPages, 'total': total},
    };
  }

  Future<List<Map<String, dynamic>>> getAvailableRiders() async {
    final res = await _client.get(
      ApiEndpoints.usersGetList,
      queryParams: {
        'role': 'rider',
        'status': 'active',
        'page': 1,
        'limit': 100
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list.cast<Map<String, dynamic>>();
  }
}
