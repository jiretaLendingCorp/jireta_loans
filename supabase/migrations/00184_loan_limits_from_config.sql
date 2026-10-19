-- supabase/migrations/00184_loan_limits_from_config.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Ang minimum/maximum loan amount ay kinokontrol na ng Head Manager sa
-- System Settings (`system_config.min_loan_amount` / `max_loan_amount`) at
-- ine-enforce ng `loans-apply` + `loans-view` (schedule preview).
--
-- Dati, may fixed CHECK ang `loans.principal_amount` (BETWEEN 3000 AND 500000)
-- — kahit taasan ng Head Manager ang maximum (hal. ₱600,000) o babaan ang
-- minimum (hal. ₱2,000), pumapalya pa rin ang insert. Pinapalitan ng mas
-- malawak na sanity check; ang config na ang humahawak ng tunay na limits.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- Alisin ang lumang principal_amount CHECK (kahit iba ang pangalan).
DO $$
DECLARE
  c RECORD;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.loans'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%principal_amount%'
  LOOP
    EXECUTE format('ALTER TABLE public.loans DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

-- Sanity check lang: positibo at may hangganan (₱100M) — ang aktwal na
-- minimum/maximum ay galing sa `system_config`.
ALTER TABLE public.loans
  ADD CONSTRAINT loans_principal_amount_check
  CHECK (principal_amount > 0 AND principal_amount <= 100000000);

COMMENT ON CONSTRAINT loans_principal_amount_check ON public.loans IS
  'Sanity bound only. The real min/max come from system_config.min_loan_amount / max_loan_amount (Head Manager → Settings) and are enforced by loans-apply / loans-view.';

COMMIT;
