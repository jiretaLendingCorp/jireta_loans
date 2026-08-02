// lib/data/models/kpi_rider_model.dart
class KpiRiderModel {
  final int totalAssignedCollections;
  final int totalCompletedCollections;
  final int totalFailedCollections;
  final double totalAmountCollected;
  final int totalCiAssignments;
  final int totalCiCompleted;

  const KpiRiderModel({
    this.totalAssignedCollections = 0,
    this.totalCompletedCollections = 0,
    this.totalFailedCollections = 0,
    this.totalAmountCollected = 0,
    this.totalCiAssignments = 0,
    this.totalCiCompleted = 0,
  });

  factory KpiRiderModel.fromJson(Map<String, dynamic> json) => KpiRiderModel(
        totalAssignedCollections:
            (json['total_assigned_collections'] as num?)?.toInt() ?? 0,
        totalCompletedCollections:
            (json['total_completed_collections'] as num?)?.toInt() ?? 0,
        totalFailedCollections:
            (json['total_failed_collections'] as num?)?.toInt() ?? 0,
        totalAmountCollected:
            (json['total_amount_collected'] as num?)?.toDouble() ?? 0,
        totalCiAssignments:
            (json['total_ci_assignments'] as num?)?.toInt() ?? 0,
        totalCiCompleted: (json['total_ci_completed'] as num?)?.toInt() ?? 0,
      );

  static KpiRiderModel empty() => const KpiRiderModel();
}
