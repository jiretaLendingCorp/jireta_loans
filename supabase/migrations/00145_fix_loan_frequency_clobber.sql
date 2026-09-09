-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00145_fix_loan_frequency_clobber.sql
-- Purpose   : Fix "loan term is always monthly" — the sync trigger on
--             loans gave the canonical uuid FK column priority on INSERT,
--             and loans.payment_frequency_id has a DEFAULT pointing at
--             'monthly'. So every loan inserted with the varchar
--             payment_frequency = 'daily' / 'weekly' (loans-apply,
--             in-office-view, kyc-view auto-convert — none of them set
--             payment_frequency_id) was silently rewritten to 'monthly'
--             by the trigger before the row landed.
--
--             FIX:
--               1) Rewrite sync_loans_lookup_ids() so on INSERT the
--                  EXPLICITLY-PROVIDED varchar code wins and the uuid FK
--                  is derived from it (the app always sends the code).
--                  The uuid->code direction is kept only as a fallback
--                  when no code was supplied. UPDATE behavior unchanged
--                  (distinct-aware both directions).
--               2) Backfill existing loans whose stored frequency is
--                  'monthly' but whose schedule due dates show daily or
--                  weekly spacing (the clobbered ones). The schedule is
--                  the ground truth: it was generated with the borrower's
--                  real frequency.
--               3) Re-sync application_loan_details for converted walk-in
--                  applications from the corrected loan frequency.
--
--             Idempotent: trigger replaced unconditionally (same name);
--             backfills only touch rows where stored frequency disagrees
--             with the inferred schedule spacing.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────
-- 1) Rewrite the loans sync trigger — code wins on INSERT
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION sync_loans_lookup_ids()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- payment_frequency <-> payment_frequency_id
  IF TG_OP = 'INSERT' THEN
    -- The app ALWAYS writes the varchar code (loans-apply, in-office-view,
    -- kyc-view auto-convert). payment_frequency_id has a DEFAULT to the
    -- 'monthly' row, so the id must never override an explicit code —
    -- otherwise daily/weekly choices get clobbered back to monthly.
    IF NEW.payment_frequency IS NOT NULL AND NEW.payment_frequency <> '' THEN
      SELECT id INTO NEW.payment_frequency_id
      FROM public.payment_frequencies WHERE code = NEW.payment_frequency;
    ELSIF NEW.payment_frequency_id IS NOT NULL THEN
      SELECT code INTO NEW.payment_frequency
      FROM public.payment_frequencies WHERE id = NEW.payment_frequency_id;
    END IF;
  ELSE
    IF NEW.payment_frequency_id IS DISTINCT FROM OLD.payment_frequency_id THEN
      SELECT code INTO NEW.payment_frequency
      FROM public.payment_frequencies WHERE id = NEW.payment_frequency_id;
    ELSIF NEW.payment_frequency IS DISTINCT FROM OLD.payment_frequency THEN
      SELECT id INTO NEW.payment_frequency_id
      FROM public.payment_frequencies WHERE code = NEW.payment_frequency;
    END IF;
  END IF;

  -- status <-> status_id (same fix; status_id has a DEFAULT to 'pending')
  IF TG_OP = 'INSERT' THEN
    IF NEW.status IS NOT NULL AND NEW.status <> '' THEN
      SELECT id INTO NEW.status_id
      FROM public.loan_statuses WHERE code = NEW.status;
    ELSIF NEW.status_id IS NOT NULL THEN
      SELECT code INTO NEW.status
      FROM public.loan_statuses WHERE id = NEW.status_id;
    END IF;
  ELSE
    IF NEW.status_id IS DISTINCT FROM OLD.status_id THEN
      SELECT code INTO NEW.status
      FROM public.loan_statuses WHERE id = NEW.status_id;
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
      SELECT id INTO NEW.status_id
      FROM public.loan_statuses WHERE code = NEW.status;
    END IF;
  END IF;

  -- employment_type snapshot (00128) — no DEFAULT on employment_type_id,
  -- keep the original distinct-aware logic.
  IF TG_OP = 'INSERT' OR NEW.employment_type_id IS DISTINCT FROM OLD.employment_type_id
     OR NEW.employment_type IS DISTINCT FROM OLD.employment_type THEN
    IF NEW.employment_type_id IS NOT NULL AND (NEW.employment_type IS NULL OR TG_OP = 'INSERT') THEN
      SELECT code INTO NEW.employment_type FROM public.employment_types WHERE id = NEW.employment_type_id;
    ELSIF NEW.employment_type IS NOT NULL THEN
      SELECT id INTO NEW.employment_type_id FROM public.employment_types WHERE code = NEW.employment_type;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_loans_lookup ON public.loans;
CREATE TRIGGER trg_sync_loans_lookup
  BEFORE INSERT OR UPDATE ON public.loans
  FOR EACH ROW EXECUTE FUNCTION sync_loans_lookup_ids();

-- ─────────────────────────────────────────────────────────────────
-- 2) Backfill existing clobbered loans from schedule spacing
--    Ground truth = loan_schedules.due_date gaps:
--      consecutive due dates 1 day apart  -> daily
--      consecutive due dates 7 days apart -> weekly
--      anything else                      -> monthly
--    Only loans whose stored frequency disagrees with the inferred one
--    AND whose inferred frequency is NOT monthly are updated (monthly is
--    the column default; those rows were never clobbered).
--
--    NOTE: trg_loan_status_flow (00032) fires on EVERY UPDATE of loans
--    and rejects any write to an already-'approved' loan, even when only
--    payment_frequency changes. It must be disabled while this data-only
--    repair runs, then re-enabled. The transaction guarantees the trigger
--    is restored even if a later statement fails.
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE public.loans DISABLE TRIGGER trg_loan_status_flow;

WITH sched_gaps AS (
  SELECT
    ls.loan_id,
    ls.installment_number,
    ls.due_date - LAG(ls.due_date) OVER (
      PARTITION BY ls.loan_id ORDER BY ls.installment_number
    ) AS gap_days
  FROM public.loan_schedules ls
),
mode_gap AS (
  SELECT
    loan_id,
    gap_days,
    ROW_NUMBER() OVER (
      PARTITION BY loan_id ORDER BY COUNT(*) DESC, MIN(installment_number)
    ) AS rn
  FROM sched_gaps
  WHERE gap_days IS NOT NULL
  GROUP BY loan_id, gap_days
),
inferred AS (
  SELECT
    loan_id,
    CASE
      WHEN gap_days = 1 THEN 'daily'
      WHEN gap_days = 7 THEN 'weekly'
      ELSE 'monthly'
    END AS frequency
  FROM mode_gap
  WHERE rn = 1
)
UPDATE public.loans l
SET payment_frequency = i.frequency,
    payment_frequency_id = pf.id
FROM inferred i
JOIN public.payment_frequencies pf ON pf.code = i.frequency
WHERE l.id = i.loan_id
  AND l.payment_frequency IS DISTINCT FROM i.frequency
  AND i.frequency <> 'monthly';

-- Restore the status-flow guard (transaction still open; safe on rollback).
ALTER TABLE public.loans ENABLE TRIGGER trg_loan_status_flow;

-- ─────────────────────────────────────────────────────────────────
-- 3) Re-sync walk-in application loan details with the corrected loan
-- ─────────────────────────────────────────────────────────────────
UPDATE public.application_loan_details ald
SET payment_frequency = l.payment_frequency,
    payment_frequency_id = l.payment_frequency_id
FROM public.loans l
WHERE l.in_office_application_id = ald.application_id
  AND ald.payment_frequency IS DISTINCT FROM l.payment_frequency;

COMMIT;