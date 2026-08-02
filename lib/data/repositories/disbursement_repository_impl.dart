// lib/data/repositories/disbursement_repository_impl.dart
import '../../domain/repositories/i_disbursement_repository.dart';
import '../datasources/remote/disbursement_remote_datasource.dart';

class DisbursementRepositoryImpl implements IDisbursementRepository {
  final DisbursementRemoteDataSource _ds;
  DisbursementRepositoryImpl(this._ds);

  @override
  Future<void> disburseGcash(Map<String, dynamic> data) async {
    await _ds.disburseGcash(
      loanId: _requiredString(data, ['loanId', 'loan_id']),
      gcashNumber: _requiredString(data, ['gcashNumber', 'gcash_number']),
    );
  }

  @override
  Future<void> disburseOfficeCash(Map<String, dynamic> data) async {
    await _ds.disburseOfficeCash(
      loanId: _requiredString(data, ['loanId', 'loan_id']),
      notes: _optionalString(data, ['notes']),
    );
  }

  @override
  Future<void> disburseRiderDelivery(Map<String, dynamic> data) async {
    await _ds.disburseRiderDelivery(
      loanId: _requiredString(data, ['loanId', 'loan_id']),
      riderId: _requiredString(data, ['riderId', 'rider_id']),
      deliveryDate: _requiredString(data, ['deliveryDate', 'delivery_date']),
      notes: _optionalString(data, ['notes']),
    );
  }

  Future<void> disbursGcash(Map<String, dynamic> data) => disburseGcash(data);

  Future<void> assignRiderDelivery(Map<String, dynamic> data) =>
      disburseRiderDelivery(data);

  String _requiredString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null) {
        final text = value.toString();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    throw ArgumentError(
        'Missing required disbursement field: ${keys.join(' or ')}');
  }

  String? _optionalString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null) {
        final text = value.toString();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    return null;
  }
}
