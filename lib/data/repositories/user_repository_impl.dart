// lib/data/repositories/user_repository_impl.dart
import '../../domain/repositories/i_user_repository.dart';
import '../datasources/remote/user_remote_datasource.dart';
import '../models/user_model.dart';

class UserRepositoryImpl implements IUserRepository {
  final UserRemoteDataSource _ds;
  UserRepositoryImpl(this._ds);

  @override
  Future<List<dynamic>> getUsers(
          {String? role, String? status, String? search, int page = 1}) =>
      _ds.getUsers(role: role, status: status, search: search, page: page);

  @override
  Future<Map<String, dynamic>> getUserList({
    String? role,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _ds.getUserList(
      role: role,
      search: search,
      page: page,
      limit: limit,
    );
    return {'users': res['data'] ?? []};
  }

  @override
  Future<UserModel> getProfile({String? userId}) =>
      _ds.getProfile(userId: userId);

  @override
  Future<void> createEmployee(Map<String, dynamic> data) =>
      _ds.createEmployee(data);

  @override
  Future<void> createRider(Map<String, dynamic> data) => _ds.createRider(data);

  @override
  Future<void> createLender(Map<String, dynamic> data) =>
      _ds.createLender(data);

  @override
  Future<void> updateProfile(String userId, Map<String, dynamic> data) =>
      _ds.updateProfile(data);

  @override
  Future<void> archive(String userId) => _ds.archive(userId);

  @override
  Future<void> unarchive(String userId) => _ds.unarchive(userId);

  @override
  Future<void> restore(String userId) => _ds.restore(userId);

  @override
  Future<void> archiveRole(String roleName) => _ds.archiveRole(roleName);

  @override
  Future<void> unarchiveRole(String roleName) => _ds.unarchiveRole(roleName);

  @override
  Future<List<Map<String, dynamic>>> getRoles() => _ds.getRoles();
}
