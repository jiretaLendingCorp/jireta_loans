// lib/presentation/features/head_manager/blacklist/providers/hm_blacklist_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/blacklist_remote_datasource.dart';

final hmBlacklistProvider = StateNotifierProvider<HmBlacklistNotifier,
    AsyncValue<Map<String, dynamic>>>((ref) {
  return HmBlacklistNotifier(sl<BlacklistRemoteDataSource>());
});

class HmBlacklistNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final BlacklistRemoteDataSource _ds;
  HmBlacklistNotifier(this._ds)
      : super(const AsyncData({'items': [], 'total': 0}));

  Future<void> loadList({String? search, int page = 1}) async {
    state = const AsyncLoading();
    try {
      final data = await _ds.getList(search: search, page: page);
      state = AsyncData(data);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<bool> addToBlacklist(
      {required String lenderId, required String reason}) async {
    try {
      await _ds.add(lenderId: lenderId, reason: reason);
      await loadList();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeFromBlacklist(String blacklistId) async {
    try {
      await _ds.remove(blacklistId: blacklistId);
      await loadList();
      return true;
    } catch (e) {
      return false;
    }
  }
}
