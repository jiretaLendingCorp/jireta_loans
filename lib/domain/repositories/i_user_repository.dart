// lib/domain/repositories/i_user_repository.dart
import '../../data/models/user_model.dart';

abstract class IUserRepository {
  Future<List<dynamic>> getUsers(
      {String? role, String? status, String? search, int page});
  Future<Map<String, dynamic>> getUserList({
    String? role,
    String? search,
    int page,
    int limit,
  });
  Future<UserModel> getProfile({String? userId});
  Future<void> createEmployee(Map<String, dynamic> data);
  Future<void> createRider(Map<String, dynamic> data);
  Future<void> createLender(Map<String, dynamic> data);
  Future<void> updateProfile(String userId, Map<String, dynamic> data);
  Future<void> archive(String userId);
}
