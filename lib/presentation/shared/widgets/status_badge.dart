// lib/presentation/shared/widgets/status_badge.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final bool small;
  final bool large;

  /// Forces a light (white) label for colored header bars — e.g. the green
  /// rider AppBar. Without this the semantic status color is applied as-is and
  /// statuses that fall back to [AppColors.textSecondary] (like `assigned`)
  /// become unreadable on top of the colored bar.
  final bool onDark;

  /// Override ng label color kapag hindi visible ang default na semantic color
  /// sa ilalim nito — hal. ang `overdue` (#B71C1C) sa dark header (#5C6370)
  /// ay 1.7:1 lang ang contrast. `null` = gamitin ang normal na status color.
  final Color? colorOverride;

  const StatusBadge({
    super.key,
    required this.status,
    this.small = false,
    this.large = false,
    this.onDark = false,
    this.colorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _config(status);
    final fs = large ? 13.0 : (small ? 10.0 : 11.0);

    // Plain text lang — hindi button, kaya walang background/border/pill.
    return Text(
      cfg.$2,
      style: TextStyle(
        fontSize: fs,
        fontWeight: onDark ? FontWeight.w700 : FontWeight.w600,
        color: onDark ? Colors.white : (colorOverride ?? cfg.$1),
        letterSpacing: onDark ? 0.4 : 0.2,
      ),
    );
  }

  static (Color, String) _config(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return (AppColors.statusPending, 'Pending');
      case 'under_review':
        return (AppColors.info, 'Under Review');
      case 'ci_required':
        return (AppColors.warning, 'CI Required');
      case 'ci_assigned':
        return (AppColors.lenderBlue, 'CI Assigned');
      case 'ci_completed':
        return (AppColors.warning, 'CI Pending Approval');
      case 'ci_approved':
        return (AppColors.riderGreen, 'CI Approved');
      case 'rider_delivery_assigned':
        return (AppColors.lenderBlue, 'Rider Delivery Assigned');
      case 'approved':
        return (AppColors.riderGreen, 'Approved');
      case 'active':
        return (AppColors.statusActive, 'Active');
      case 'completed':
        return (AppColors.statusCompleted, 'Completed');
      case 'rejected':
        return (AppColors.statusRejected, 'Rejected');
      case 'reversed':
        // Reversal ng bayad (`payment.status = 'reversed'`) — kung wala ito,
        // bagsak ito sa default: gray na `textSecondary` at uppercase na
        // "REVERSED", na hindi mabasa sa dark na header ng receipt.
        return (AppColors.statusRejected, 'Reversed');
      case 'cancelled':
        return (AppColors.textSecondary, 'Cancelled');
      case 'overdue':
        return (AppColors.statusOverdue, 'Overdue');
      case 'verified':
        return (AppColors.riderGreen, 'Verified');
      case 'submitted':
        return (AppColors.info, 'Submitted');
      case 'suspended':
        return (AppColors.error, 'Suspended');
      case 'whitelisted':
        return (AppColors.statusActive, 'Whitelisted');
      case 'archived':
        return (AppColors.textSecondary, 'Archived');
      case 'blacklisted':
        return (AppColors.error, 'Blacklisted');
      case 'accepted':
        return (AppColors.riderGreen, 'Accepted');
      case 'requested':
        return (AppColors.warning, 'Requested');
      case 'declined':
        return (AppColors.error, 'Declined');
      case 'in_progress':
        return (AppColors.warning, 'In Progress');
      case 'pending_approval':
        return (AppColors.warning, 'Pending Approval');
      case 'draft':
        return (AppColors.textSecondary, 'Draft');
      case 'converted':
        return (AppColors.riderGreen, 'Converted');
      default:
        return (
          AppColors.textSecondary,
          status.replaceAll('_', ' ').toUpperCase()
        );
    }
  }
}
