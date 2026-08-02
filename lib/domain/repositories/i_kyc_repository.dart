// lib/domain/repositories/i_kyc_repository.dart
import '../../data/models/kyc_document_model.dart';

abstract class IKycRepository {
  Future<void> submitKyc(List<Map<String, dynamic>> documents);
  Future<void> verifyKyc(String kycDocId, String action,
      {String? rejectionNotes});
  Future<Map<String, dynamic>> getKycList({String? status, int page});
  Future<KycStatusModel> getKycStatus();
}
