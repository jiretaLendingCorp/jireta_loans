// lib/data/repositories/kyc_repository_impl.dart
import '../../domain/repositories/i_kyc_repository.dart';
import '../datasources/remote/kyc_remote_datasource.dart';
import '../models/kyc_document_model.dart';

class KycRepositoryImpl implements IKycRepository {
  final KycRemoteDataSource _ds;
  KycRepositoryImpl(this._ds);

  @override
  Future<void> submitKyc(List<Map<String, dynamic>> documents) =>
      _ds.submitKyc(documents);

  @override
  Future<void> verifyKyc(String kycDocId, String action,
          {String? rejectionNotes}) =>
      _ds.verifyKyc(
          kycDocId: kycDocId, action: action, rejectionNotes: rejectionNotes);

  @override
  Future<Map<String, dynamic>> getKycList({String? status, int page = 1}) =>
      _ds.getKycList(status: status, page: page);

  @override
  Future<KycStatusModel> getKycStatus() => _ds.getKycStatus();
}
