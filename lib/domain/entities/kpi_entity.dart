// lib/domain/entities/kpi_entity.dart
class KpiHeadManagerEntity {
  final int totalEmployees;
  final int totalRiders;
  final int totalLenders;
  final int totalLoanApplications;
  final int totalApproved;
  final int totalRejected;
  final int totalActive;
  final int totalCompleted;
  final int totalOverdue;
  final double totalReleasedAmount;
  final double totalCollected;
  final double totalOutstanding;
  final double totalInterestEarned;
  final double totalPenalties;
  final double totalRevenue;
  final int totalCollectionTransactions;
  final int totalCiAssignments;
  final int totalReportExports;
  final int totalPendingAccountUpgrade;

  const KpiHeadManagerEntity({
    required this.totalEmployees,
    required this.totalRiders,
    required this.totalLenders,
    required this.totalLoanApplications,
    required this.totalApproved,
    required this.totalRejected,
    required this.totalActive,
    required this.totalCompleted,
    required this.totalOverdue,
    required this.totalReleasedAmount,
    required this.totalCollected,
    required this.totalOutstanding,
    required this.totalInterestEarned,
    required this.totalPenalties,
    required this.totalRevenue,
    required this.totalCollectionTransactions,
    required this.totalCiAssignments,
    required this.totalReportExports,
    required this.totalPendingAccountUpgrade,
  });
}

class KpiEmployeeEntity {
  final int totalLendersManaged;
  final int totalApplicationsProcessed;
  final int totalApproved;
  final int totalRejected;
  final int totalActive;
  final int totalCompleted;
  final int totalCollectionsManaged;

  const KpiEmployeeEntity({
    required this.totalLendersManaged,
    required this.totalApplicationsProcessed,
    required this.totalApproved,
    required this.totalRejected,
    required this.totalActive,
    required this.totalCompleted,
    required this.totalCollectionsManaged,
  });
}

class KpiRiderEntity {
  final int totalAssignedCollections;
  final int totalCompletedCollections;
  final int totalFailedCollections;
  final double totalAmountCollected;
  final int totalCiAssignments;
  final int totalCiCompleted;

  const KpiRiderEntity({
    required this.totalAssignedCollections,
    required this.totalCompletedCollections,
    required this.totalFailedCollections,
    required this.totalAmountCollected,
    required this.totalCiAssignments,
    required this.totalCiCompleted,
  });
}

class KpiLenderEntity {
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

  const KpiLenderEntity({
    required this.totalApplications,
    required this.totalApproved,
    required this.totalRejected,
    required this.totalActive,
    required this.totalCompleted,
    required this.totalBorrowed,
    required this.totalPaid,
    required this.remainingBalance,
    required this.totalInterestPaid,
    required this.totalPenaltiesPaid,
  });
}
