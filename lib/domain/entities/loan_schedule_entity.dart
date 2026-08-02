// lib/domain/entities/loan_schedule_entity.dart
class LoanScheduleEntity {
  final String id;
  final String loanId;
  final int periodNumber;
  final DateTime dueDate;
  final double amountDue;
  final double amountPaid;
  final String status;
  final DateTime? paidAt;

  const LoanScheduleEntity({
    required this.id,
    required this.loanId,
    required this.periodNumber,
    required this.dueDate,
    required this.amountDue,
    required this.amountPaid,
    required this.status,
    this.paidAt,
  });
}
