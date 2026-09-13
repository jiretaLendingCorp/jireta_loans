-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00160_remove_loan_number_from_notifications.sql
-- Purpose   : Alisin ang loan number (hal. LN-2026-0001) sa lahat ng
--             notification body para hindi ito makita ng lender/user.
--             Ang mga notification na ito ay gawa ng DB functions na
--             apply_loan_term_penalties() (00152) at
--             send_payment_due_reminders() (00151), kaya i-rewrite ang
--             kanilang prosrc gamit ang pg_get_functiondef + replace —
--             para hindi na kailangang kopyahin muli ang buong function.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

DO $$
DECLARE
  v_def TEXT;
BEGIN
  -- ── apply_loan_term_penalties() ─────────────────────────────────────
  v_def := pg_get_functiondef('public.apply_loan_term_penalties()'::regprocedure);

  -- Penalty notification: "Your loan LN-... reached the end of its term..."
  v_def := replace(
    v_def,
    '''Your loan '' || v_loan.loan_number || '' reached the end of its term with an unpaid balance. ''',
    '''Your loan reached the end of its term with an unpaid balance. '''
  );

  -- Account-paused notification: "...because your loan LN-... also reached..."
  v_def := replace(
    v_def,
    '''Your account has been paused because your loan '' || v_loan.loan_number',
    '''Your account has been paused because a loan'''
  );

  EXECUTE v_def;

  -- ── send_payment_due_reminders() ────────────────────────────────────
  v_def := pg_get_functiondef('public.send_payment_due_reminders()'::regprocedure);

  -- Payment due: "... payment of ₱... for loan LN-... is due on ..."
  v_def := replace(
    v_def,
    ''' for loan '' || v_target.loan_number || '' is due on ''',
    ''' is due on '''
  );

  EXECUTE v_def;
END $$;

COMMIT;
