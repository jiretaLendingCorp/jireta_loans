// lib/domain/repositories/i_kpi_repository.dart
import '../../data/models/kpi_employee_model.dart';
import '../../data/models/kpi_head_manager_model.dart';
import '../../data/models/kpi_lender_model.dart';
import '../../data/models/kpi_rider_model.dart';

abstract class IKpiRepository {
  Future<KpiHeadManagerModel> getHeadManagerKpi({String? month});
  Future<KpiEmployeeModel> getEmployeeKpi();
  Future<KpiRiderModel> getRiderKpi();
  Future<KpiLenderModel> getLenderKpi();
}
