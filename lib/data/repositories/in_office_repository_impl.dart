// lib/data/repositories/in_office_repository_impl.dart
import '../../domain/repositories/i_in_office_repository.dart';
import '../datasources/remote/in_office_remote_datasource.dart';

class InOfficeRepositoryImpl implements IInOfficeRepository {
  final InOfficeRemoteDataSource _ds;
  InOfficeRepositoryImpl(this._ds);

  @override
  Future<Map<String, dynamic>> createDraft() => _ds.createDraft();

  @override
  Future<void> saveStep(
          String applicationId, int step, Map<String, dynamic> data) =>
      _ds.saveStep(applicationId: applicationId, step: step, data: data);

  @override
  Future<void> submitApplication(String applicationId) =>
      _ds.submitApplication(applicationId: applicationId);

  @override
  Future<List<dynamic>> getInOfficeList({String? status, int page = 1}) =>
      _ds.getApplicationList(status: status, page: page);
}
