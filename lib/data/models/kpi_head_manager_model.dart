// lib/data/models/kpi_head_manager_model.dart
class MonthlyKpiPoint {
  final String month;
  final int applications;
  final double released;
  final double collected;

  const MonthlyKpiPoint({
    required this.month,
    required this.applications,
    required this.released,
    required this.collected,
  });

  factory MonthlyKpiPoint.fromJson(Map<String, dynamic> json) {
    return MonthlyKpiPoint(
      month: json['month']?.toString() ?? '',
      applications: (json['applications'] as num?)?.toInt() ?? 0,
      released: (json['released'] as num?)?.toDouble() ?? 0,
      collected: (json['collected'] as num?)?.toDouble() ?? 0,
    );
  }
}

class KpiHeadManagerModel {
  final int totalHeadManagers;
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
  final List<MonthlyKpiPoint> monthlySeries;
  final Map<String, int> loanStatusBreakdown;
  final int pendingBucket;
  // Monthly metadata — when isMonthly==true, values above are filtered to selectedMonth
  final String? selectedMonth; // YYYY-MM or null (lifetime)
  final bool isMonthly;

  const KpiHeadManagerModel({
    this.totalHeadManagers = 0,
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
    this.monthlySeries = const [],
    this.loanStatusBreakdown = const {},
    this.pendingBucket = 0,
    this.selectedMonth,
    this.isMonthly = false,
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
    final rawBreakdown = json['loan_status_breakdown'] as Map<String, dynamic>?;
    Map<String, int> breakdown = {};
    if (rawBreakdown != null) {
      breakdown = rawBreakdown.map((k, v) => MapEntry(k, (v as num).toInt()));
    }
    return KpiHeadManagerModel(
      totalHeadManagers: (json['total_head_managers'] as num?)?.toInt() ?? 0,
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
      totalPendingAccountUpgrade:
          (json['total_pending_account_upgrade'] as num?)?.toInt() ?? 0,
      monthlySeries: (json['monthly_series'] as List<dynamic>? ?? [])
          .map((e) => MonthlyKpiPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      loanStatusBreakdown: breakdown,
      pendingBucket: (json['pending_bucket'] as num?)?.toInt() ?? 0,
      selectedMonth: json['selected_month']?.toString(),
      isMonthly: (json['is_monthly'] == true) || (json['period'] == 'monthly'),
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
        loanStatusBreakdown: {},
        pendingBucket: 0,
        selectedMonth: null,
        isMonthly: false,
      );
}
