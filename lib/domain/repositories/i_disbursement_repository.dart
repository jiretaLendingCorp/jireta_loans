// lib/domain/repositories/i_disbursement_repository.dart
abstract class IDisbursementRepository {
  Future<void> disburseGcash(Map<String, dynamic> data);
  Future<void> disburseOfficeCash(Map<String, dynamic> data);
  Future<void> disburseRiderDelivery(Map<String, dynamic> data);
}
