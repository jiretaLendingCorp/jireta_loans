// lib/presentation/features/head_manager/audit/audit_action_catalog.dart
//
// Single source of truth for the `action` values written to the `audit_logs`
// table by the Supabase Edge Functions (via _shared/audit.ts `writeAuditLog`).
// The audit screen's filter dropdown must use EXACTLY these values or filters
// silently return empty lists.
class AuditActionCatalog {
  AuditActionCatalog._();

  static const List<String> actions = [
    // Auth
    'password_reset',
    'force_password_changed',
    'password_changed',
    'employee_registered',
    // Users
    'user_created',
    'create_rider',
    'create_lender',
    'archive_user',
    'update_profile',
    // Loans
    'loan_applied',
    'loan_approve',
    'loan_reject',
    'loan_cancel',
    'request_ci',
    'apply_penalty',
    // Payments
    'payment_recorded',
    'payment_reverse',
    'generate_gcash_link',
    'xendit_payment_verified',
    // Collections
    'collection_request',
    'collection_assign',
    'collection_accept',
    'collection_decline',
    'collection_record',
    'collection_upload_proof',
    // Disbursements
    'disbursement_selected',
    'disburse_gcash',
    'disburse_office_cash',
    'disburse_rider_delivery',
    'disbursement_delivery_proof',
    'disbursement_webhook',
    // Credit investigation
    'ci_assigned',
    'ci_accept',
    'ci_decline',
    'ci_submit_report',
    'ci_upload_documents',
    // Account upgrade
    'account_upgrade_submit',
    // In-office
    'in_office_draft_created',
    'in_office_submitted',
    // System
    'system_config_updated',
    'sms_template_updated',
    'notification_sent',
    'report_export',
  ];

  /// Legacy labels from the original UI that never matched a backend action.
  /// Kept as documentation so nobody reintroduces them as filter values.
  static const Map<String, String> legacyMappings = {
    'login': 'login/logout are tracked in auth_logs, not audit_logs',
    'logout': 'login/logout are tracked in auth_logs, not audit_logs',
    'loan_created': 'loan_applied',
    'loan_approved': 'loan_approve',
    'loan_rejected': 'loan_reject',
    'payment': 'payment_recorded',
    'settings_changed': 'system_config_updated / sms_template_updated',
  };

  static String label(String action) {
    if (action.isEmpty) return action;
    return action
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}