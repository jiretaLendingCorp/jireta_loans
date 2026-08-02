// lib/data/models/kpi_employee_model.dart
class KpiEmployeeModel {
  final int totalLendersManaged;
  final int totalApplicationsProcessed;
  final int totalApprovedLoans;
  final int totalRejectedLoans;
  final int totalActiveLoans;
  final int totalCompletedLoans;
  final int totalCollectionsManaged;

  const KpiEmployeeModel({
    required this.totalLendersManaged,
    required this.totalApplicationsProcessed,
    required this.totalApprovedLoans,
    required this.totalRejectedLoans,
    required this.totalActiveLoans,
    required this.totalCompletedLoans,
    required this.totalCollectionsManaged,
  });

  factory KpiEmployeeModel.fromJson(Map<String, dynamic> json) =>
      KpiEmployeeModel(
        totalLendersManaged:
            (json['total_lenders_managed'] as num?)?.toInt() ?? 0,
        totalApplicationsProcessed:
            (json['total_applications_processed'] as num?)?.toInt() ?? 0,
        totalApprovedLoans:
            (json['total_approved_loans'] as num?)?.toInt() ?? 0,
        totalRejectedLoans:
            (json['total_rejected_loans'] as num?)?.toInt() ?? 0,
        totalActiveLoans: (json['total_active_loans'] as num?)?.toInt() ?? 0,
        totalCompletedLoans:
            (json['total_completed_loans'] as num?)?.toInt() ?? 0,
        totalCollectionsManaged:
            (json['total_collections_managed'] as num?)?.toInt() ?? 0,
      );

  static KpiEmployeeModel empty() => const KpiEmployeeModel(
        totalLendersManaged: 0,
        totalApplicationsProcessed: 0,
        totalApprovedLoans: 0,
        totalRejectedLoans: 0,
        totalActiveLoans: 0,
        totalCompletedLoans: 0,
        totalCollectionsManaged: 0,
      );
}
