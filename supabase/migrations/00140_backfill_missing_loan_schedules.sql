-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00140_backfill_missing_loan_schedules.sql
-- Purpose   : Backfill loan_schedules for ACTIVE / OVERDUE loans that
--             have NO schedules at all. Loans created before schedule
--             generation was introduced (or whose schedules were lost)
--             show "No schedule available" in the lender app even though
--             the loan is active. This migration regenerates their
--             schedules using the SAME math as the backend scheduler
--             (flat 20% interest, per-frequency interval from the loan
--             start date).
--
--             Idempotent: only touches loans with zero schedules.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

DO $$
DECLARE
  r RECORD;
  v_interest      NUMERIC;
  v_total         NUMERIC;
  v_installments  INTEGER;
  v_interval_days INTEGER;
  v_base          NUMERIC;
  v_start         DATE;
  v_existing      INTEGER;
BEGIN
  FOR r IN
    SELECT
      l.id,
      l.principal_amount,
      l.interest_rate,
      l.payment_frequency,
      l.term_periods,
      l.term_days,
      l.installment_amount,
      l.created_at,
      d.disbursed_at
    FROM public.loans l
    LEFT JOIN LATERAL (
      SELECT disbursed_at
      FROM public.disbursements
      WHERE loan_id = l.id
      ORDER BY created_at ASC
      LIMIT 1
    ) d ON true
    WHERE l.status IN ('active', 'overdue')
  LOOP
    SELECT COUNT(*) INTO v_existing
    FROM public.loan_schedules
    WHERE loan_id = r.id;
    IF v_existing > 0 THEN
      CONTINUE;
    END IF;

    -- Start counting due dates from when the money was released.
    v_start := COALESCE((r.disbursed_at)::date, (r.created_at)::date);

    v_interest := ROUND(r.principal_amount * COALESCE(r.interest_rate, 20) / 100, 2);
    v_total := ROUND(r.principal_amount + v_interest, 2);

    IF r.payment_frequency = 'daily' THEN
      v_interval_days := 1;
    ELSIF r.payment_frequency = 'weekly' THEN
      v_interval_days := 7;
    ELSE
      v_interval_days := 30;
    END IF;

    -- Number of installments: the loan's chosen term_periods, else the
    -- maximum allowed for its frequency within the term (same as backend).
    IF COALESCE(r.term_periods, 0) > 0 THEN
      v_installments := r.term_periods;
    ELSIF r.payment_frequency = 'daily' THEN
      v_installments := GREATEST(1, COALESCE(r.term_days, 40));
    ELSIF r.payment_frequency = 'weekly' THEN
      v_installments := GREATEST(1, CEIL(COALESCE(r.term_days, 40)::NUMERIC / 7));
    ELSE
      v_installments := GREATEST(1, CEIL(COALESCE(r.term_days, 40)::NUMERIC / 30));
    END IF;

    v_base := ROUND(v_total / v_installments, 2);

    INSERT INTO public.loan_schedules (loan_id, installment_number, due_date, amount_due, created_at, updated_at)
    SELECT
      r.id,
      gs.n,
      (v_start + ((gs.n * v_interval_days) || ' days')::interval)::date,
      CASE
        WHEN gs.n = v_installments THEN ROUND(v_total - v_base * (v_installments - 1), 2)
        ELSE v_base
      END,
      now_manila(),
      now_manila()
    FROM generate_series(1, v_installments) AS gs(n);

    -- Keep the loan's installment_amount in sync with the regenerated base.
    IF COALESCE(r.installment_amount, 0) <= 0 THEN
      UPDATE public.loans
      SET installment_amount = v_base
      WHERE id = r.id
        AND (installment_amount IS NULL OR installment_amount <= 0);
    END IF;
  END LOOP;
END $$;

COMMIT;