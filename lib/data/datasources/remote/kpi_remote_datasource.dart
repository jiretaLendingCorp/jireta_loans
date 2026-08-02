// lib/data/datasources/remote/kpi_remote_datasource.dart
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../models/kpi_employee_model.dart';
import '../../models/kpi_head_manager_model.dart';
import '../../models/kpi_lender_model.dart';
import '../../models/kpi_rider_model.dart';

class KpiRemoteDataSource {
  final DioClient _client;
  KpiRemoteDataSource(this._client);

  Future<KpiHeadManagerModel> getHeadManagerKpi() async {
    final res = await _client.get(ApiEndpoints.kpiHeadManager);
    return KpiHeadManagerModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<KpiEmployeeModel> getEmployeeKpi() async {
    final res = await _client.get(ApiEndpoints.kpiEmployee);
    return KpiEmployeeModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<KpiRiderModel> getRiderKpi() async {
    final res = await _client.get(ApiEndpoints.kpiRider);
    return KpiRiderModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<KpiLenderModel> getLenderKpi() async {
    final res = await _client.get(ApiEndpoints.kpiLender);
    return KpiLenderModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<KpiHeadManagerModel> getHeadManagerKpis() => getHeadManagerKpi();
  Future<KpiEmployeeModel> getEmployeeKpis() => getEmployeeKpi();
  Future<KpiRiderModel> getRiderKpis() => getRiderKpi();
  Future<KpiLenderModel> getLenderKpis() => getLenderKpi();
}
