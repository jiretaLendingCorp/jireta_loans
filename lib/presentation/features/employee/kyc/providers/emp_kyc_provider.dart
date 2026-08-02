// lib/presentation/features/employee/kyc/providers/emp_kyc_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/kyc_remote_datasource.dart';

final empKycProvider =
    StateNotifierProvider<EmpKycNotifier, AsyncValue<Map<String, dynamic>>>(
        (ref) {
  return EmpKycNotifier(sl<KycRemoteDataSource>());
});

class EmpKycNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final KycRemoteDataSource _ds;
  EmpKycNotifier(this._ds) : super(const AsyncData({'items': [], 'total': 0}));

  Future<void> loadList({String? status, String? search, int page = 1}) async {
    state = const AsyncLoading();
    try {
      final data =
          await _ds.getList(status: status, search: search, page: page);
      state = AsyncData(data);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<bool> verify(
      {required String kycDocId,
      required String action,
      String? rejectionNotes}) async {
    try {
      await _ds.verify(
          kycDocId: kycDocId, action: action, rejectionNotes: rejectionNotes);
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
}
