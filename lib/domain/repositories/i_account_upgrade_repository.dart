// lib/domain/repositories/i_account_upgrade_repository.dart
import '../../data/models/account_upgrade_document_model.dart';

abstract class IAccountUpgradeRepository {
  Future<void> submitAccountUpgrade(List<Map<String, dynamic>> documents);
  Future<void> verifyAccountUpgrade(String accountUpgradeDocId, String action,
      {String? rejectionNotes});
  Future<Map<String, dynamic>> accountUpgradeGetList(
      {String? status, int page});
  Future<AccountUpgradeStatusModel> accountUpgradeGetStatus();
}
