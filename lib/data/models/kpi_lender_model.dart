// lib/data/models/kpi_lender_model.dart
class KpiLenderModel {
  final int totalApplications;
  final int totalApproved;
  final int totalRejected;
  final int totalActive;
  final int totalCompleted;
  final double totalBorrowed;
  final double totalPaid;
  final double remainingBalance;
  final double totalInterestPaid;
  final double totalPenaltiesPaid;
  final String accountUpgradeStatus;

  const KpiLenderModel({
    this.totalApplications = 0,
    this.totalApproved = 0,
    this.totalRejected = 0,
    this.totalActive = 0,
    this.totalCompleted = 0,
    this.totalBorrowed = 0,
    this.totalPaid = 0,
    this.remainingBalance = 0,
    this.totalInterestPaid = 0,
    this.totalPenaltiesPaid = 0,
    this.accountUpgradeStatus = 'not_submitted',
  });

  factory KpiLenderModel.fromJson(Map<String, dynamic> json) => KpiLenderModel(
        totalApplications: (json['total_applications'] as num?)?.toInt() ?? 0,
        totalApproved: (json['total_approved'] as num?)?.toInt() ?? 0,
        totalRejected: (json['total_rejected'] as num?)?.toInt() ?? 0,
        totalActive: (json['total_active'] as num?)?.toInt() ?? 0,
        totalCompleted: (json['total_completed'] as num?)?.toInt() ?? 0,
        totalBorrowed: (json['total_borrowed'] as num?)?.toDouble() ?? 0,
        totalPaid: (json['total_paid'] as num?)?.toDouble() ?? 0,
        remainingBalance: (json['remaining_balance'] as num?)?.toDouble() ?? 0,
        totalInterestPaid:
            (json['total_interest_paid'] as num?)?.toDouble() ?? 0,
        totalPenaltiesPaid:
            (json['total_penalties_paid'] as num?)?.toDouble() ?? 0,
        accountUpgradeStatus: json['account_upgrade_status'] as String? ?? 'not_submitted',
      );
}
