// lib/core/utils/helpers.dart
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String generateIdempotencyKey() => _uuid.v4();

String generateUuid() => _uuid.v4();

class AppHelpers {
  AppHelpers._();

  static String generateIdempotencyKey() => _uuid.v4();

  static String generateUuid() => _uuid.v4();

  static bool isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  static String formatRole(String role) {
    switch (role) {
      case 'head_manager':
        return 'Head Manager';
      case 'employee':
        return 'Employee';
      case 'rider':
        return 'Rider';
      case 'lender':
        return 'Lender';
      default:
        return role;
    }
  }

  static String loanStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'under_review':
        return 'Under Review';
      case 'ci_required':
        return 'CI Required';
      case 'ci_assigned':
        return 'CI Assigned';
      case 'ci_completed':
        return 'CI Completed';
      case 'approved':
        return 'Approved';
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      case 'overdue':
        return 'Overdue';
      default:
        return status;
    }
  }

  static String accountUpgradeStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'submitted':
        return 'Under Review';
      case 'verified':
        return 'Verified';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }
}

bool isValidCoordinate(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

String formatRole(String role) {
  switch (role) {
    case 'head_manager':
      return 'Head Manager';
    case 'employee':
      return 'Employee';
    case 'rider':
      return 'Rider';
    case 'lender':
      return 'Lender';
    default:
      return role;
  }
}

String loanStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Pending';
    case 'under_review':
      return 'Under Review';
    case 'ci_required':
      return 'CI Required';
    case 'ci_assigned':
      return 'CI Assigned';
    case 'ci_completed':
      return 'CI Completed';
    case 'approved':
      return 'Approved';
    case 'active':
      return 'Active';
    case 'completed':
      return 'Completed';
    case 'rejected':
      return 'Rejected';
    case 'cancelled':
      return 'Cancelled';
    case 'overdue':
      return 'Overdue';
    default:
      return status;
  }
}

String accountUpgradeStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Pending';
    case 'submitted':
      return 'Under Review';
    case 'verified':
      return 'Verified';
    case 'rejected':
      return 'Rejected';
    default:
      return status;
  }
}
