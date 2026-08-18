import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/features/head_manager/audit/audit_action_catalog.dart';

void main() {
  group('AuditActionCatalog', () {
    test('contains every action the backend writes to audit_logs', () {
      final expected = {
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
      };
      expect(AuditActionCatalog.actions.toSet(), expected);
    });

    test('does not contain the legacy names that never match the backend', () {
      for (final legacy in AuditActionCatalog.legacyMappings.keys) {
        expect(
          AuditActionCatalog.actions,
          isNot(contains(legacy)),
          reason: "'$legacy' is a legacy UI label, not a backend action",
        );
      }
    });

    test('labels are unique and human readable', () {
      final labels = AuditActionCatalog.actions.map(AuditActionCatalog.label);
      expect(labels.toSet().length, labels.length,
          reason: 'labels must be unique for the dropdown');
      for (final label in labels) {
        expect(label.trim(), isNotEmpty);
        expect(RegExp(r'^[A-Z]').hasMatch(label), isTrue,
            reason: 'label should start with a capital letter');
        expect(label.contains('_'), isFalse,
            reason: 'labels should not leak raw snake_case values');
      }
    });

    test('legacyMappings documents the correct replacements', () {
      expect(AuditActionCatalog.legacyMappings['login'],
          contains('auth_logs'));
      expect(AuditActionCatalog.legacyMappings['logout'],
          contains('auth_logs'));
      expect(AuditActionCatalog.legacyMappings['loan_created'],
          'loan_applied');
      expect(AuditActionCatalog.legacyMappings['loan_approved'],
          'loan_approve');
      expect(AuditActionCatalog.legacyMappings['loan_rejected'],
          'loan_reject');
      expect(AuditActionCatalog.legacyMappings['payment'],
          'payment_recorded');
      expect(AuditActionCatalog.legacyMappings['settings_changed'],
          contains('system_config_updated'));
    });
  });
}
