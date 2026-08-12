// lib/data/repositories/account_upgrade_repository_impl.dart
import '../../domain/repositories/i_account_upgrade_repository.dart';
import '../datasources/remote/account_upgrade_remote_datasource.dart';
import '../models/account_upgrade_document_model.dart';

class AccountUpgradeRepositoryImpl implements IAccountUpgradeRepository {
  final AccountUpgradeRemoteDataSource _ds;
  AccountUpgradeRepositoryImpl(this._ds);

  @override
  Future<void> submitAccountUpgrade(List<Map<String, dynamic>> documents) =>
      _ds.submitAccountUpgrade(documents);

  @override
  Future<void> verifyAccountUpgrade(String accountUpgradeDocId, String action,
          {String? rejectionNotes}) =>
      _ds.verifyAccountUpgrade(
          accountUpgradeDocId: accountUpgradeDocId,
          action: action,
          rejectionNotes: rejectionNotes);

  @override
  Future<Map<String, dynamic>> accountUpgradeGetList(
          {String? status, int page = 1}) =>
      _ds.accountUpgradeGetList(status: status, page: page);

  @override
  Future<AccountUpgradeStatusModel> accountUpgradeGetStatus() =>
      _ds.accountUpgradeGetStatus();
}
