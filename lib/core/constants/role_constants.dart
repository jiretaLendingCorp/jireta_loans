// lib/core/constants/role_constants.dart
/// Role names as stored in `public.roles.name`.
/// Historical naming: `lender` is SEMANTICALLY the BORROWER / CLIENT — the
/// person who applies for and repays the loan (see roles.description = 'Borrower
/// who applies for loans' and DB VIEW `borrower_profiles` alias for
/// `lender_profiles`). For new code/docs/ERD, prefer `borrower` terminology;
/// the DB migration 00111 adds VIEWs `borrower_profiles`, `borrower_loans`, etc.
/// as non-breaking alias. The raw value remains 'lender' for backward compat
/// with `auth_role()` RLS, Supabase Realtime channels, and Edge Functions.
class RoleConstants {
  RoleConstants._();

  static const String headManager = 'head_manager';
  static const String employee = 'employee';
  static const String rider = 'rider';
  static const String lender = 'lender';

  /// Alias for [lender] — semantically BORROWER. Use in new code for clarity.
  /// Value is still 'lender' until DB role rename (v2, see 00109/00111).
  static const String borrower = lender;

  static const List<String> webRoles = [headManager, employee];
  static const List<String> mobileRoles = [rider, lender];
  static const List<String> staffRoles = [headManager, employee];
  static const List<String> allRoles = [headManager, employee, rider, lender];

  /// Roles that represent the BORROWER side (single entry but alias-friendly).
  static const List<String> borrowerRoles = [lender];
}
