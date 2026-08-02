// lib/core/constants/role_constants.dart
class RoleConstants {
  RoleConstants._();

  static const String headManager = 'head_manager';
  static const String employee = 'employee';
  static const String rider = 'rider';
  static const String lender = 'lender';

  static const List<String> webRoles = [headManager, employee];
  static const List<String> mobileRoles = [rider, lender];
  static const List<String> staffRoles = [headManager, employee];
  static const List<String> allRoles = [headManager, employee, rider, lender];
}
