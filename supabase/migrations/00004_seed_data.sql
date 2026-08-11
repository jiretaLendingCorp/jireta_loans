-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00004_seed_data.sql
-- Purpose   : Consolidated seed data — roles, SMS templates, report
--             templates, and system configuration (from 00004_seed_data).
--             All inserts are idempotent (ON CONFLICT DO NOTHING).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

INSERT INTO roles (name, description) VALUES
  ('head_manager', 'Full system access - web portal'),
  ('employee',     'Loan processing and management - web portal'),
  ('rider',        'Field agent for CI and collections - mobile'),
  ('lender',       'Borrower who applies for loans - mobile')
ON CONFLICT (name) DO NOTHING;

INSERT INTO sms_templates (template_key, title, body) VALUES
  ('payment_reminder',
   'Payment Due Reminder',
   'Dear {first_name}, your Jireta Loans installment of PHP {amount} is due on {due_date}. Please pay on time to avoid penalties. Thank you!'),
  ('otp_verification',
   'OTP Verification',
   'Your Jireta Loans OTP is: {otp}. Valid for 10 minutes. Do not share this code.'),
  ('loan_approved',
   'Loan Approved',
   'Congratulations {first_name}! Your loan of PHP {amount} has been approved. Disbursement will follow shortly.'),
  ('loan_rejected',
   'Loan Application Update',
   'Dear {first_name}, we regret to inform you that your loan application has been declined. Please contact our office for details.')
ON CONFLICT (template_key) DO NOTHING;

INSERT INTO report_templates (template_key, title, description, parameters_schema) VALUES
  ('loan_summary',         'Loan Summary Report',          'Overview of all loan applications by status and period',         '{"date_from":{"type":"date"},"date_to":{"type":"date"},"status":{"type":"string","optional":true}}'),
  ('collection_report',    'Collection Report',            'Summary of all cash and GCash collections by rider and period',  '{"date_from":{"type":"date"},"date_to":{"type":"date"},"rider_id":{"type":"uuid","optional":true}}'),
  ('payment_report',       'Payment Report',               'All payments received including method breakdown',               '{"date_from":{"type":"date"},"date_to":{"type":"date"},"method":{"type":"string","optional":true}}'),
  ('lender_report',        'Lender/Borrower Report',       'All registered lenders with KYC and loan status',               '{"status":{"type":"string","optional":true},"kyc_status":{"type":"string","optional":true}}'),
  ('rider_report',         'Rider Report',                 'Rider performance: CI completions and collections',              '{"date_from":{"type":"date"},"date_to":{"type":"date"},"rider_id":{"type":"uuid","optional":true}}'),
  ('employee_report',      'Employee Report',              'Employee activity and loan processing metrics',                  '{"date_from":{"type":"date"},"date_to":{"type":"date"}}'),
  ('financial_report',     'Financial Summary Report',     'Revenue, interest earned, penalties, outstanding balances',      '{"date_from":{"type":"date"},"date_to":{"type":"date"}}'),
  ('revenue_report',       'Revenue Report',               'Breakdown of income sources: interest + penalties',             '{"date_from":{"type":"date"},"date_to":{"type":"date"}}'),
  ('interest_report',      'Interest Earned Report',       'Interest earned per loan and cumulative totals',                '{"date_from":{"type":"date"},"date_to":{"type":"date"}}'),
  ('penalty_report',       'Penalty Collection Report',    'All penalties applied with basis and amounts',                  '{"date_from":{"type":"date"},"date_to":{"type":"date"}}'),
  ('overdue_report',       'Overdue Loans Report',         'All overdue loans with outstanding balances and contact info',  '{"as_of_date":{"type":"date","optional":true}}'),
  ('audit_report',         'Audit Trail Report',           'System audit logs filtered by action, user, or table',         '{"date_from":{"type":"date"},"date_to":{"type":"date"},"action":{"type":"string","optional":true}}'),
  ('ci_report',            'Credit Investigation Report',  'All CI assignments with status and rider performance',          '{"date_from":{"type":"date"},"date_to":{"type":"date"},"rider_id":{"type":"uuid","optional":true}}'),
  ('disbursement_report',  'Disbursement Report',          'All loan disbursements by method, amount, and status',         '{"date_from":{"type":"date"},"date_to":{"type":"date"},"method":{"type":"string","optional":true}}')
ON CONFLICT (template_key) DO NOTHING;

INSERT INTO system_config (config_key, config_value, description) VALUES
  ('min_loan_amount',      '3000',    'Minimum loan amount in PHP'),
  ('max_loan_amount',      '500000',  'Maximum loan amount in PHP'),
  ('interest_rate',        '20',      'Standard interest rate percentage'),
  ('penalty_rate',         '20',      'Penalty rate percentage applied after 30 days overdue'),
  ('otp_expiry_minutes',   '10',      'OTP expiry time in minutes'),
  ('max_login_attempts',   '5',       'Maximum failed login attempts before lockout'),
  ('lockout_minutes',      '15',      'Account lockout duration in minutes'),
  ('payment_reminder_days','2',       'Days before due date to send SMS reminder'),
  ('app_name',             'Jireta Loans & Credit Corp 1966', 'Application display name'),
  ('support_phone',        '09000000000', 'Office support contact number')
ON CONFLICT (config_key) DO NOTHING;

COMMIT;
