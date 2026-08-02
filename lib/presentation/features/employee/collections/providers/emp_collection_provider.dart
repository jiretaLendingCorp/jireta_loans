// lib/presentation/features/employee/collections/providers/emp_collection_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';

final empCollectionListProvider = StateNotifierProvider<EmpCollectionNotifier,
    AsyncValue<Map<String, dynamic>>>((ref) {
  return EmpCollectionNotifier(
      sl<CollectionRemoteDataSource>(), sl<UserRemoteDataSource>());
});

class EmpCollectionNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final CollectionRemoteDataSource _ds;
  final UserRemoteDataSource _userDs;
  EmpCollectionNotifier(this._ds, this._userDs)
      : super(const AsyncData({'items': [], 'total': 0}));

  Future<void> loadList({String? status, String? riderId, int page = 1}) async {
    state = const AsyncLoading();
    try {
      final data =
          await _ds.getList(status: status, riderId: riderId, page: page);
      state = AsyncData(data);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<bool> assign(
      {required String loanScheduleId,
      required String riderId,
      String? notes,
      String? schedule}) async {
    try {
      await _ds.assign(
          loanScheduleId: loanScheduleId,
          riderId: riderId,
          collectionSchedule: schedule,
          notes: notes);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableRiders() async {
    try {
      final data = await _userDs.getList(
          role: 'rider', status: 'active', page: 1, limit: 100);
      return List<Map<String, dynamic>>.from(data['items'] ?? []);
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getDetail(String collectionId) async {
    try {
      final res = await _ds.getList(page: 1, limit: 1000);
      final items = (res['items'] as List?) ?? [];
      for (final it in items) {
        if (it is Map && it['id'] == collectionId) {
          return Map<String, dynamic>.from(it);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
