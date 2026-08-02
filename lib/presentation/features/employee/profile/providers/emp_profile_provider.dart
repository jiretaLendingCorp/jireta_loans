// lib/presentation/features/employee/profile/providers/emp_profile_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';

final empProfileProvider =
    StateNotifierProvider<EmpProfileNotifier, AsyncValue<UserModel?>>((ref) {
  return EmpProfileNotifier(sl<UserRemoteDataSource>());
});

class EmpProfileNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  final UserRemoteDataSource _ds;
  EmpProfileNotifier(this._ds) : super(const AsyncData(null));

  Future<void> loadProfile() async {
    state = const AsyncLoading();
    try {
      final data = await _ds.getProfile();
      state = AsyncData(data);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<bool> updateProfile(Map<String, dynamic> data) async {
    try {
      await _ds.updateProfile(data);
      await loadProfile();
      return true;
    } catch (e) {
      return false;
    }
  }
}
