-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00138_auto_overdue_penalty.sql
-- Purpose   : Business rule — "kapag nag overdue ang payment ni lender,
--             madadagdagan ng 20% ang utang niya."
--             1) penalty_logs.applied_by becomes nullable so the system
--                (not a staff user) can record the automatic penalty.
--             2) auto_mark_overdue_loans() now inserts a 20% penalty log
--                for every loan it flips to 'overdue' (once only).
--             3) auto_mark_overdue_loans() is scheduled via pg_cron
--                (best-effort, guarded like expire_overdue_assignments).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Allow system-applied penalties (applied_by = NULL)
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE penalty_logs
  ALTER COLUMN applied_by DROP NOT NULL;

-- ─────────────────────────────────────────────────────────────────────
-- 2) auto_mark_overdue_loans() — marks overdue AND applies the 20%
--    penalty automatically so the lender's debt really does grow by 20%.
--    Uses Manila time; skips loans that already have a penalty log.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION auto_mark_overdue_loans()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_loan RECORD;
BEGIN
  -- Mark loans overdue when an installment is 30+ days past due with no
  -- verified payment (existing rule, Manila time).
  UPDATE loans
  SET status = 'overdue'
  WHERE status = 'active'
    AND id IN (
      SELECT ls.loan_id
      FROM loan_schedules ls
      LEFT JOIN payments p ON p.loan_schedule_id = ls.id AND p.status = 'verified'
      WHERE ls.due_date < (now_manila() - INTERVAL '30 days')::date
      GROUP BY ls.loan_id, ls.id
      HAVING COALESCE(SUM(p.amount), 0) = 0
    );

  -- Apply the automatic 20% penalty for every loan that just went overdue
  -- and does not already have a penalty log (idempotent).
  FOR v_loan IN
    SELECT id, principal_amount, interest_rate
    FROM loans
    WHERE status = 'overdue'
      AND NOT EXISTS (
        SELECT 1 FROM penalty_logs pl WHERE pl.loan_id = loans.id
      )
  LOOP
    INSERT INTO penalty_logs (
      loan_id,
      applied_by,
      penalty_basis,
      penalty_rate,
      penalty_amount,
      reason
    ) VALUES (
      v_loan.id,
      NULL,
      ROUND((v_loan.principal_amount * (1 + COALESCE(v_loan.interest_rate, 20) / 100))::numeric, 2),
      20.00,
      ROUND((v_loan.principal_amount * (1 + COALESCE(v_loan.interest_rate, 20) / 100) * 0.20)::numeric, 2),
      'Automatic 20% penalty applied — loan overdue by 30+ days'
    );
  END LOOP;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Schedule the overdue check via pg_cron (best effort). If pg_cron is
--    unavailable (local dev / hosted without cron) this is skipped — the
--    function can still be invoked manually or from an edge function.
-- ─────────────────────────────────────────────────────────────────────
DO $cron_do$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron extension not available — skipping cron schedule for auto_mark_overdue_loans';
    RETURN;
  END;

  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    RAISE NOTICE 'cron schema not present — skipping pg_cron schedule for auto_mark_overdue_loans';
    RETURN;
  END IF;

  BEGIN
    PERFORM cron.unschedule('auto_mark_overdue_loans_daily');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  PERFORM cron.schedule(
    'auto_mark_overdue_loans_daily',
    '0 0 * * *',
    $cron_job$ SELECT public.auto_mark_overdue_loans(); $cron_job$
  );

  RAISE NOTICE 'pg_cron job auto_mark_overdue_loans_daily scheduled daily at midnight';

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Could not schedule pg_cron job (non-fatal): %', SQLERRM;
END $cron_do$;

COMMIT;