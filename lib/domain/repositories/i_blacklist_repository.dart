// lib/domain/repositories/i_blacklist_repository.dart
abstract class IBlacklistRepository {
  Future<void> addToBlacklist(String lenderId, String reason);
  Future<void> removeFromBlacklist(String lenderId);
  Future<Map<String, dynamic>> getBlacklistList({int page});
}
