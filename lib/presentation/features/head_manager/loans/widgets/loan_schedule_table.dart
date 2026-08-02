// lib/presentation/features/head_manager/loans/widgets/loan_schedule_table.dart
import 'package:flutter/material.dart';

import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/status_badge.dart';

class LoanScheduleTable extends StatelessWidget {
  final List<dynamic> schedules;
  final bool compact;

  const LoanScheduleTable({
    super.key,
    required this.schedules,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (schedules.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Text(
          'No payment schedule available',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.surface),
            headingTextStyle: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 12 : 13,
            ),
            dataTextStyle: TextStyle(
              color: AppColors.textPrimary,
              fontSize: compact ? 12 : 13,
            ),
            columnSpacing: compact ? 16 : 24,
            horizontalMargin: compact ? 12 : 16,
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('Due Date')),
              DataColumn(label: Text('Amount Due')),
              DataColumn(label: Text('Amount Paid')),
              DataColumn(label: Text('Balance')),
              DataColumn(label: Text('Status')),
            ],
            rows: List.generate(schedules.length, (i) {
              final s = schedules[i] as Map<String, dynamic>;
              final amountDue = (s['amount_due'] as num?)?.toDouble() ?? 0.0;
              final amountPaid = (s['amount_paid'] as num?)?.toDouble() ?? 0.0;
              final balance = amountDue - amountPaid;
              final status = s['status'] as String? ?? 'pending';
              final dueDate = s['due_date'] as String?;

              Color rowColor = Colors.transparent;
              if (status == 'paid') {
                rowColor = const Color(0xFFF1FBF4);
              } else if (status == 'overdue') {
                rowColor = const Color(0xFFFFF3F3);
              } else if (status == 'partial') {
                rowColor = const Color(0xFFFFFBF0);
              }

              return DataRow(
                color: WidgetStateProperty.all(rowColor),
                cells: [
                  DataCell(Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  )),
                  DataCell(Text(
                    dueDate != null
                        ? DateTime.tryParse(dueDate)?.toPhilippineDate() ??
                            dueDate
                        : '—',
                  )),
                  DataCell(Text(
                    amountDue.toCurrency,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  )),
                  DataCell(Text(
                    amountPaid.toCurrency,
                    style: TextStyle(
                      color: amountPaid > 0
                          ? AppColors.success
                          : AppColors.textSecondary,
                      fontWeight:
                          amountPaid > 0 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  )),
                  DataCell(Text(
                    balance.toCurrency,
                    style: TextStyle(
                      color: balance > 0 ? AppColors.error : AppColors.success,
                      fontWeight: FontWeight.w500,
                    ),
                  )),
                  DataCell(StatusBadge(status: status)),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
