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

  static bool parseBoolValue(dynamic value, {bool fallback = false}) =>
      parseBool(value, fallback: fallback);

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
      case 'rider_delivery_assigned':
        return 'Rider Delivery Assigned';
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

/// Robust bool parser: handles String 'true'/'false', '1'/'0', int 0/1
bool parseBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v == 'true' || v == 't' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == 'f' || v == '0' || v == 'no' || v == '') return false;
  }
  return fallback;
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
    case 'rider_delivery_assigned':
      return 'Rider Delivery Assigned';
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
