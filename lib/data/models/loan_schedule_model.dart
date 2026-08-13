// lib/data/models/loan_schedule_model.dart
class LoanScheduleModel {
  final String id;
  final String loanId;
  final int periodNumber;
  final DateTime dueDate;
  final double amountDue;
  final double amountPaid;
  final String status;
  final DateTime? paidAt;

  const LoanScheduleModel({
    required this.id,
    required this.loanId,
    required this.periodNumber,
    required this.dueDate,
    required this.amountDue,
    required this.amountPaid,
    required this.status,
    this.paidAt,
  });

  factory LoanScheduleModel.fromJson(Map<String, dynamic> json) =>
      LoanScheduleModel(
        id: json['id'] ?? '',
        loanId: json['loan_id'] ?? '',
        periodNumber: (json['period_number'] as num?)?.toInt() ?? 0,
        dueDate: json['due_date'] != null
            ? DateTime.parse(json['due_date'])
            : DateTime.now(),
        amountDue: (json['amount_due'] as num?)?.toDouble() ?? 0,
        amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0,
        status: json['status'] ?? 'pending',
        paidAt:
            json['paid_at'] != null ? DateTime.parse(json['paid_at']) : null,
      );

  double get remainingAmount => amountDue - amountPaid;
  bool get isPaid => status == 'paid';
  bool get isOverdue => status == 'pending' && dueDate.isBefore(DateTime.now());

  String get statusLabel {
    switch (status) {
      case 'paid':
        return 'Paid';
      case 'partial':
        return 'Partial';
      case 'pending':
        return isOverdue ? 'Overdue' : 'Pending';
      default:
        return status;
    }
  }
}

class LoanSchedulePreviewModel {
  final double totalPayable;
  final double interestAmount;
  final double installmentAmount;
  final int termDays;
  final List<SchedulePeriod> periods;

  const LoanSchedulePreviewModel({
    required this.totalPayable,
    required this.interestAmount,
    required this.installmentAmount,
    required this.termDays,
    required this.periods,
  });

  factory LoanSchedulePreviewModel.fromJson(Map<String, dynamic> json) =>
      LoanSchedulePreviewModel(
        totalPayable: (json['total_payable'] as num?)?.toDouble() ?? 0,
        interestAmount: (json['interest_amount'] as num?)?.toDouble() ?? 0,
        installmentAmount:
            (json['installment_amount'] as num?)?.toDouble() ?? 0,
        termDays: (json['term_days'] as num?)?.toInt() ?? 0,
        periods: (json['periods'] as List? ?? [])
            .map((e) => SchedulePeriod.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SchedulePeriod {
  final int periodNumber;
  final DateTime dueDate;
  final double amount;

  const SchedulePeriod({
    required this.periodNumber,
    required this.dueDate,
    required this.amount,
  });

  factory SchedulePeriod.fromJson(Map<String, dynamic> json) => SchedulePeriod(
        periodNumber: (json['period_number'] as num?)?.toInt() ?? 0,
        dueDate: json['due_date'] != null
            ? DateTime.parse(json['due_date'])
            : DateTime.now(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}
