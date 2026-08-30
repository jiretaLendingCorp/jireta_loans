// lib/presentation/shared/widgets/status_badge.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final bool small;
  final bool large;

  const StatusBadge({
    super.key,
    required this.status,
    this.small = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _config(status);
    final fs = large ? 13.0 : (small ? 10.0 : 11.0);
    final px = large ? 12.0 : (small ? 8.0 : 10.0);
    final py = large ? 6.0 : (small ? 3.0 : 4.0);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: px, vertical: py),
      decoration: BoxDecoration(
        color: cfg.$2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cfg.$1.withValues(alpha: 0.3)),
      ),
      child: Text(
        cfg.$3,
        style: TextStyle(
          fontSize: fs,
          fontWeight: FontWeight.w600,
          color: cfg.$1,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static (Color, Color, String) _config(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return (AppColors.statusPending, AppColors.statusPendingBg, 'Pending');
      case 'under_review':
        return (AppColors.info, AppColors.infoLight, 'Under Review');
      case 'ci_required':
        return (AppColors.warning, AppColors.warningLight, 'CI Required');
      case 'ci_assigned':
        return (AppColors.lenderBlue, const Color(0xFFF3E5F5), 'CI Assigned');
      case 'ci_completed':
        return (AppColors.warning, AppColors.warningLight, 'CI Pending Approval');
      case 'ci_approved':
        return (AppColors.riderGreen, AppColors.successLight, 'CI Approved');
      case 'rider_delivery_assigned':
        return (AppColors.lenderBlue, const Color(0xFFE3F2FD),
            'Rider Delivery Assigned');
      case 'approved':
        return (AppColors.riderGreen, AppColors.successLight, 'Approved');
      case 'active':
        return (AppColors.statusActive, AppColors.statusActiveBg, 'Active');
      case 'completed':
        return (
          AppColors.statusCompleted,
          AppColors.statusCompletedBg,
          'Completed'
        );
      case 'rejected':
        return (
          AppColors.statusRejected,
          AppColors.statusRejectedBg,
          'Rejected'
        );
      case 'cancelled':
        return (AppColors.textSecondary, const Color(0xFFF5F5F5), 'Cancelled');
      case 'overdue':
        return (AppColors.statusOverdue, AppColors.statusOverdueBg, 'Overdue');
      case 'verified':
        return (AppColors.riderGreen, AppColors.successLight, 'Verified');
      case 'submitted':
        return (AppColors.info, AppColors.infoLight, 'Submitted');
      case 'suspended':
        return (AppColors.error, AppColors.errorLight, 'Suspended');
      case 'whitelisted':
        return (
          AppColors.statusActive,
          AppColors.statusActiveBg,
          'Whitelisted'
        );
      case 'archived':
        return (AppColors.textSecondary, const Color(0xFFF5F5F5), 'Archived');
      case 'blacklisted':
        return (AppColors.error, AppColors.errorLight, 'Blacklisted');
      case 'accepted':
        return (AppColors.riderGreen, AppColors.successLight, 'Accepted');
      case 'requested':
        return (AppColors.warning, AppColors.warningLight, 'Requested');
      case 'declined':
        return (AppColors.error, AppColors.errorLight, 'Declined');
      case 'in_progress':
        return (AppColors.warning, AppColors.warningLight, 'In Progress');
      case 'draft':
        return (AppColors.textSecondary, const Color(0xFFF5F5F5), 'Draft');
      case 'converted':
        return (AppColors.riderGreen, AppColors.successLight, 'Converted');
      default:
        return (
          AppColors.textSecondary,
          const Color(0xFFF5F5F5),
          status.replaceAll('_', ' ').toUpperCase()
        );
    }
  }
}
