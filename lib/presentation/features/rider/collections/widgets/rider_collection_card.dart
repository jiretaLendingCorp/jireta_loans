// lib/presentation/features/rider/collections/widgets/rider_collection_card.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../shared/widgets/status_badge.dart';

class RiderCollectionCard extends StatelessWidget {
  final CollectionAssignmentModel collection;

  const RiderCollectionCard({super.key, required this.collection});

  @override
  Widget build(BuildContext context) {
    final schedule = collection.loanSchedule;
    final borrowerName =
        schedule?['loan']?['lender']?['user']?['full_name'] as String? ??
            'Unknown Borrower';
    final amountDue = (schedule?['amount_due'] as num?)?.toDouble() ?? 0;
    final dueDate = schedule?['due_date'] as String?;

    return GestureDetector(
      onTap: () => context.push(
        RouteConstants.riderCollectionDetails
            .replaceFirst(':id', collection.id),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.riderGreen.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.riderGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.payments_outlined,
                        color: AppColors.riderGreen, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          borrowerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dueDate != null
                              ? 'Due: ${DateTime.tryParse(dueDate)?.toPhilippineDate() ?? dueDate}'
                              : 'No due date',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(status: collection.status),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _InfoChip(
                    icon: Icons.monetization_on_outlined,
                    label: 'Amount Due',
                    value: amountDue.toPeso(),
                    color: AppColors.riderGreen,
                  ),
                  if (collection.collectionSchedule != null)
                    _InfoChip(
                      icon: Icons.schedule_outlined,
                      label: 'Scheduled',
                      value: collection.collectionSchedule!.toPhilippineDate(),
                      color: AppColors.info,
                    ),
                  const _InfoChip(
                    icon: Icons.arrow_forward_ios,
                    label: '',
                    value: 'View',
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoChip(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label.isNotEmpty)
              Text(label,
                  style: TextStyle(
                      fontSize: 10, color: color.withValues(alpha: 0.7))),
            Text(value,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ],
    );
  }
}
