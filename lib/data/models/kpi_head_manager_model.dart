// lib/data/models/kpi_head_manager_model.dart
class KpiHeadManagerModel {
  final int totalEmployees;
  final int totalRiders;
  final int totalLenders;
  final int totalLoanApplications;
  final int totalApprovedLoans;
  final int totalRejectedLoans;
  final int totalActiveLoans;
  final int totalCompletedLoans;
  final int totalOverdueLoans;
  final double totalLoanAmountReleased;
  final double totalAmountCollected;
  final double totalOutstandingBalance;
  final double totalInterestEarned;
  final double totalPenaltiesCollected;
  final double totalRevenue;
  final int totalCollectionTransactions;
  final int totalCiAssignments;
  final int totalReportExports;
  final int totalPendingAccountUpgrade;

  const KpiHeadManagerModel({
    required this.totalEmployees,
    required this.totalRiders,
    required this.totalLenders,
    required this.totalLoanApplications,
    required this.totalApprovedLoans,
    required this.totalRejectedLoans,
    required this.totalActiveLoans,
    required this.totalCompletedLoans,
    required this.totalOverdueLoans,
    required this.totalLoanAmountReleased,
    required this.totalAmountCollected,
    required this.totalOutstandingBalance,
    required this.totalInterestEarned,
    required this.totalPenaltiesCollected,
    required this.totalRevenue,
    required this.totalCollectionTransactions,
    required this.totalCiAssignments,
    required this.totalReportExports,
    required this.totalPendingAccountUpgrade,
  });

  int get totalApproved => totalApprovedLoans;
  int get totalRejected => totalRejectedLoans;
  int get totalActive => totalActiveLoans;
  int get totalCompleted => totalCompletedLoans;
  int get totalOverdue => totalOverdueLoans;
  double get totalReleased => totalLoanAmountReleased;
  double get totalCollected => totalAmountCollected;
  double get totalOutstanding => totalOutstandingBalance;
  double get totalInterest => totalInterestEarned;
  double get totalPenalties => totalPenaltiesCollected;
  int get totalCollectionTxns => totalCollectionTransactions;

  factory KpiHeadManagerModel.fromJson(Map<String, dynamic> json) {
    return KpiHeadManagerModel(
      totalEmployees: (json['total_employees'] as num?)?.toInt() ?? 0,
      totalRiders: (json['total_riders'] as num?)?.toInt() ?? 0,
      totalLenders: (json['total_lenders'] as num?)?.toInt() ?? 0,
      totalLoanApplications:
          (json['total_loan_applications'] as num?)?.toInt() ?? 0,
      totalApprovedLoans: (json['total_approved_loans'] as num?)?.toInt() ?? 0,
      totalRejectedLoans: (json['total_rejected_loans'] as num?)?.toInt() ?? 0,
      totalActiveLoans: (json['total_active_loans'] as num?)?.toInt() ?? 0,
      totalCompletedLoans:
          (json['total_completed_loans'] as num?)?.toInt() ?? 0,
      totalOverdueLoans: (json['total_overdue_loans'] as num?)?.toInt() ?? 0,
      totalLoanAmountReleased:
          (json['total_loan_amount_released'] as num?)?.toDouble() ?? 0,
      totalAmountCollected:
          (json['total_amount_collected'] as num?)?.toDouble() ?? 0,
      totalOutstandingBalance:
          (json['total_outstanding_balance'] as num?)?.toDouble() ?? 0,
      totalInterestEarned:
          (json['total_interest_earned'] as num?)?.toDouble() ?? 0,
      totalPenaltiesCollected:
          (json['total_penalties_collected'] as num?)?.toDouble() ?? 0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0,
      totalCollectionTransactions:
          (json['total_collection_transactions'] as num?)?.toInt() ?? 0,
      totalCiAssignments: (json['total_ci_assignments'] as num?)?.toInt() ?? 0,
      totalReportExports: (json['total_report_exports'] as num?)?.toInt() ?? 0,
      totalPendingAccountUpgrade: (json['total_pending_account_upgrade'] as num?)?.toInt() ?? 0,
    );
  }

  static KpiHeadManagerModel empty() => const KpiHeadManagerModel(
    totalEmployees: 0,
    totalRiders: 0,
    totalLenders: 0,
    totalLoanApplications: 0,
    totalApprovedLoans: 0,
    totalRejectedLoans: 0,
    totalActiveLoans: 0,
    totalCompletedLoans: 0,
    totalOverdueLoans: 0,
    totalLoanAmountReleased: 0,
    totalAmountCollected: 0,
    totalOutstandingBalance: 0,
    totalInterestEarned: 0,
    totalPenaltiesCollected: 0,
    totalRevenue: 0,
    totalCollectionTransactions: 0,
    totalCiAssignments: 0,
    totalReportExports: 0,
    totalPendingAccountUpgrade: 0,
  );
}
