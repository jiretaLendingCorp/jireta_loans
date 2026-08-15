// lib/presentation/features/employee/account_upgrade/providers/emp_account_upgrade_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/account_upgrade_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

final empAccountUpgradeProvider = AutoDisposeStateNotifierProvider<
    EmpAccountUpgradeNotifier, AsyncValue<Map<String, dynamic>>>((ref) {
  return EmpAccountUpgradeNotifier(sl<AccountUpgradeRemoteDataSource>());
});

class EmpAccountUpgradeNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>>
    with RealtimeRefreshMixin {
  final AccountUpgradeRemoteDataSource _ds;
  EmpAccountUpgradeNotifier(this._ds)
      : super(const AsyncData({'items': [], 'total': 0})) {
    bindRealtimeRefresh(['account_upgrade_documents', 'lender_profiles'],
        refresh: () => loadList(silent: true));
  }

  Future<void> loadList(
      {String? status, String? search, int page = 1, bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    try {
      final data =
          await _ds.getList(status: status, search: search, page: page);
      state = AsyncData(data);
    } catch (e, s) {
      if (silent && state is AsyncData) return;
      state = AsyncError(e, s);
    }
  }

  Future<bool> verify(
      {required String accountUpgradeDocId,
      required String action,
      String? rejectionNotes}) async {
    try {
      await _ds.verify(
          accountUpgradeDocId: accountUpgradeDocId,
          action: action,
          rejectionNotes: rejectionNotes);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyAll(
      {required String lenderId,
      required String action,
      String? rejectionNotes}) async {
    try {
      await _ds.verifyAllAccountUpgrade(
          lenderId: lenderId, action: action, rejectionNotes: rejectionNotes);
      await loadList();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getStatus(String lenderId) async {
    try {
      return await _ds.getStatus(lenderId: lenderId);
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getDetails(
      {String? accountUpgradeDocId, String? lenderId}) async {
    try {
      return await _ds.getDetails(
          accountUpgradeDocId: accountUpgradeDocId, lenderId: lenderId);
    } catch (e) {
      return null;
    }
  }
}
