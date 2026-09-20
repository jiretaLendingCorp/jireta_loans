// lib/data/datasources/remote/user_remote_datasource.dart
import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/utils/logger.dart';
import '../../models/user_model.dart';

class UserRemoteDataSource {
  final DioClient _client;
  UserRemoteDataSource(this._client);

  /// Isinasama sa TOP LEVEL ang nested na `employee_profiles` /
  /// `rider_profiles` / `lender_profiles` ng tugon ng
  /// `users-manage?fn=get-profile` (pinapanatili pa rin ang nested na key).
  ///
  /// BUG na inaayos nito: ang [UserModel.fromJson] ay TOP-LEVEL ang binabasa
  /// (`json['gender']`, `json['civil_status']`, `json['date_of_birth']`,
  /// `json['position']`) pero NESTED ang isinasagot ng server. Kung hindi ito
  /// i-flatten, laging `null` ang gender / civil status / date of birth ng
  /// head manager at employee — kaya hindi sila na-pre-fill sa Personal
  /// Details dialog at hindi rin malaman kung kumpleto na ang account.
  static Map<String, dynamic> flattenRoleProfile(Map<String, dynamic> row) {
    final merged = <String, dynamic>{...row};
    for (final key in const [
      'employee_profiles',
      'rider_profiles',
      'lender_profiles',
    ]) {
      final raw = row[key];
      // Ang embed ay pwedeng List o Map (depende sa cardinality).
      final obj = raw is List ? (raw.isEmpty ? null : raw.first) : raw;
      if (obj is Map) {
        for (final entry in obj.entries) {
          // `putIfAbsent` — huwag patungan ang may laman nang top-level value.
          merged.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
    return merged;
  }

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

  Future<Map<String, dynamic>> createHeadManager(
      Map<String, dynamic> data) async {
    final res = await _client.post(
      ApiEndpoints.usersCreateHeadManager,
      data: data,
    );
    return res.data as Map<String, dynamic>;
  }

  /// Head Manager resets another user's password back to the default
  /// (12345678) and forces a change on next login.
  Future<void> resetPassword(String userId) async {
    await _client.patch(
      ApiEndpoints.usersResetPassword,
      data: {'user_id': userId},
    );
  }

  Future<UserModel> getProfile({String? userId}) async {
    try {
      final res = await _client.get(
        ApiEndpoints.usersGetProfile,
        queryParams: userId != null ? {'user_id': userId} : null,
      );
      final raw = res.data;
      if (raw is! Map<String, dynamic>) {
        AppLogger.e('[UserRemote] getProfile unexpected raw type: ${raw.runtimeType} $raw');
        throw DioException(requestOptions: RequestOptions(path: ApiEndpoints.usersGetProfile), message: 'Invalid profile response');
      }
      final data = raw['user'];
      if (data == null) {
        AppLogger.e('[UserRemote] getProfile user is null, raw=$raw userId=$userId');
        throw DioException(requestOptions: RequestOptions(path: ApiEndpoints.usersGetProfile), message: 'User not found', response: Response(requestOptions: RequestOptions(path: ApiEndpoints.usersGetProfile), statusCode: 404, data: raw));
      }
      return UserModel.fromJson(flattenRoleProfile(data as Map<String, dynamic>));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      AppLogger.e('[UserRemote] getProfile failed userId=$userId status=$status body=$body path=${e.requestOptions.path} q=${e.requestOptions.queryParameters}');
      rethrow;
    } catch (e, s) {
      AppLogger.e('[UserRemote] getProfile unexpected error userId=$userId $e', e, s);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getProfileMap({String? userId}) async {
    try {
      final res = await _client.get(
        ApiEndpoints.usersGetProfile,
        queryParams: userId != null ? {'user_id': userId} : null,
      );
      final data = (res.data as Map<String, dynamic>)['user'];
      if (data == null) throw Exception('User not found');
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      AppLogger.e('[UserRemote] getProfileMap failed userId=$userId status=${e.response?.statusCode} body=${e.response?.data}');
      rethrow;
    }
  }

  Future<List<UserModel>> getUsers({
    String? role,
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    String? dateFrom,
    String? dateTo,
  }) async {
    final res = await _client.get(
      ApiEndpoints.usersGetList,
      queryParams: {
        if (role != null) 'role': role,
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
        if (search != null) 'search': search,
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
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

  /// Inaalis ang automatic account pause ng isang lender (escalation rule ng
  /// pagka-pangalawa nang term default, migration 00152). Head Manager o
  /// Employee lang ang pinapayagan; lender accounts lang, at 'paused' →
  /// 'active' lamang ang maaaring baguhin ng action na ito.
  Future<void> unpauseLender(String userId) async {
    await _client.patch(ApiEndpoints.usersUnpauseLender,
        data: {'user_id': userId});
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
