// lib/data/repositories/kpi_repository_impl.dart
import '../../domain/repositories/i_kpi_repository.dart';
import '../datasources/remote/kpi_remote_datasource.dart';
import '../models/kpi_employee_model.dart';
import '../models/kpi_head_manager_model.dart';
import '../models/kpi_lender_model.dart';
import '../models/kpi_rider_model.dart';

class KpiRepositoryImpl implements IKpiRepository {
  final KpiRemoteDataSource _ds;
  KpiRepositoryImpl(this._ds);

  @override
  Future<KpiHeadManagerModel> getHeadManagerKpi() => _ds.getHeadManagerKpi();

  @override
  Future<KpiEmployeeModel> getEmployeeKpi() => _ds.getEmployeeKpi();

  @override
  Future<KpiRiderModel> getRiderKpi() => _ds.getRiderKpi();

  @override
  Future<KpiLenderModel> getLenderKpi() => _ds.getLenderKpi();
}
