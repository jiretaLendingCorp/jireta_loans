// lib/data/repositories/blacklist_repository_impl.dart
import '../../domain/repositories/i_blacklist_repository.dart';
import '../datasources/remote/blacklist_remote_datasource.dart';

class BlacklistRepositoryImpl implements IBlacklistRepository {
  final BlacklistRemoteDataSource _ds;
  BlacklistRepositoryImpl(this._ds);

  @override
  Future<void> addToBlacklist(String lenderId, String reason) =>
      _ds.addToBlacklist(lenderId: lenderId, reason: reason);

  @override
  Future<void> removeFromBlacklist(String lenderId) =>
      _ds.removeFromBlacklist(lenderId: lenderId);

  @override
  Future<Map<String, dynamic>> getBlacklistList({int page = 1}) =>
      _ds.getBlacklist(page: page);
}
