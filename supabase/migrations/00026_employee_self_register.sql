-- Migration : 00026_employee_self_register.sql
-- Purpose   : Employee self-registration on the website app.
--             Registered employees are created with account_status = 'pending'
--             and can only sign in once the head manager approves the account
--             (edit user → status 'active'). Add the 'pending' code to
--             user_account_statuses so the FK reference below resolves.

INSERT INTO user_account_statuses (code, label, sort_order)
VALUES ('pending', 'Pending Approval', 3)
ON CONFLICT (code) DO NOTHING;