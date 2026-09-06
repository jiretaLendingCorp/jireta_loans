-- =====================================================================
-- Migration: 00128_loan_financial_emergency_snapshot.sql
-- Purpose  : Move financial details + emergency contact from lender_profiles
--            (per-lender, wrong) to loans (per-loan snapshot, correct).
--
-- REVIEWER REQUEST (Tagalog):
--   "UNG FINANCIAL DETAILS AT EMERGENCY CONTACT AY DAPAT WALA SA
--    LENDER PROFILES DAPAT UN AY NASA LOAN UN"
--
-- RATIONALE:
--   Employment / income / emergency contact change per application.
--   Storing them on lender_profiles means every new loan overwrites history
--   and staff cannot see what the borrower declared AT APPLICATION TIME.
--   Correct 3NF: snapshot them on loans (+ loan_emergency_contacts 1:N),
--   same as in-office flow already does via application_employment_info /
--   application_emergency_contacts. lender_profiles keeps identity only
--   (gender, civil_status, dob, gcash, account_upgrade_status).
--
-- DESIGN — Additive, not destructive (zero-downtime, follows 00110):
--   • ADD loans.employment_type (+ employment_type_id uuid canonical),
--     employer_name, monthly_income, source_of_funds.
--   • CREATE loan_emergency_contacts (loan_id FK -> loans.id).
--   • Backfill loans from lender_profiles + loan_emergency_contacts from
--     emergency_contacts (per lender -> per loan fan-out).
--   • Keep lender_profiles columns + emergency_contacts table for now as
--     DEPRECATED/LEGACY (COMMENT), so old app versions don't 500.
--     Next v2 migration may DROP after Flutter fully migrates.
--   • New code (loans-apply / loans-view / kyc-submit / users-manage)
--     reads/writes ONLY the loan snapshot.
--
-- Idempotent: every DDL guarded by catalog checks.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─────────────────────────────────────────────────────────────────
-- 1) loans: per-loan financial snapshot columns
-- ─────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='loans' AND column_name='employment_type') THEN
    ALTER TABLE public.loans ADD COLUMN employment_type VARCHAR(30) REFERENCES employment_types(code);
    RAISE NOTICE 'Added loans.employment_type';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='loans' AND column_name='employment_type_id') THEN
    ALTER TABLE public.loans ADD COLUMN employment_type_id UUID REFERENCES employment_types(id);
    RAISE NOTICE 'Added loans.employment_type_id';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='loans' AND column_name='employer_name') THEN
    ALTER TABLE public.loans ADD COLUMN employer_name VARCHAR(255);
    RAISE NOTICE 'Added loans.employer_name';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='loans' AND column_name='monthly_income') THEN
    ALTER TABLE public.loans ADD COLUMN monthly_income DECIMAL(12,2) CHECK (monthly_income >= 0);
    RAISE NOTICE 'Added loans.monthly_income';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='loans' AND column_name='source_of_funds') THEN
    ALTER TABLE public.loans ADD COLUMN source_of_funds VARCHAR(50);
    RAISE NOTICE 'Added loans.source_of_funds';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_loans_employment_type ON public.loans(employment_type);
CREATE INDEX IF NOT EXISTS idx_loans_employment_type_id ON public.loans(employment_type_id);

-- FK for employment_type_id if missing (varchar FK already via REFERENCES)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
    WHERE c.conrelid='public.loans'::regclass AND c.contype='f'
      AND a.attname='employment_type_id' AND c.confrelid='public.employment_types'::regclass
  ) THEN
    BEGIN
      ALTER TABLE public.loans ADD CONSTRAINT fk_loans_employment_type_id
        FOREIGN KEY (employment_type_id) REFERENCES public.employment_types(id) NOT VALID;
      ALTER TABLE public.loans VALIDATE CONSTRAINT fk_loans_employment_type_id;
      RAISE NOTICE 'Validated FK fk_loans_employment_type_id';
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'FK fk_loans_employment_type_id NOT VALID: %', SQLERRM;
    END;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- 2) loan_emergency_contacts — per-loan 1:N (replaces per-lender emergency_contacts)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.loan_emergency_contacts (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id        UUID NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  name           VARCHAR(255) NOT NULL,
  relationship   VARCHAR(50)  NOT NULL REFERENCES relationship_types(code),
  relationship_id UUID REFERENCES relationship_types(id),
  phone_number   VARCHAR(20)  NOT NULL,
  address        TEXT,
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loan_emergency_loan_id ON public.loan_emergency_contacts(loan_id);
CREATE INDEX IF NOT EXISTS idx_loan_emergency_relationship_id ON public.loan_emergency_contacts(relationship_id);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_loan_emergency_loan_phone') THEN
    ALTER TABLE public.loan_emergency_contacts
      ADD CONSTRAINT uq_loan_emergency_loan_phone UNIQUE (loan_id, phone_number);
  END IF;
EXCEPTION WHEN OTHERS THEN RAISE WARNING 'uq_loan_emergency_loan_phone: %', SQLERRM;
END $$;

-- FK relationship_id if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
    WHERE c.conrelid='public.loan_emergency_contacts'::regclass AND c.contype='f'
      AND a.attname='relationship_id' AND c.confrelid='public.relationship_types'::regclass
  ) THEN
    BEGIN
      ALTER TABLE public.loan_emergency_contacts ADD CONSTRAINT fk_loan_emergency_relationship_id
        FOREIGN KEY (relationship_id) REFERENCES public.relationship_types(id) NOT VALID;
      ALTER TABLE public.loan_emergency_contacts VALIDATE CONSTRAINT fk_loan_emergency_relationship_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'FK fk_loan_emergency_relationship_id NOT VALID: %', SQLERRM;
    END;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- 3) Backfill loans snapshot from lender_profiles (history-preserving)
-- ─────────────────────────────────────────────────────────────────
UPDATE public.loans l
SET employment_type = lp.employment_type,
    employment_type_id = lp.employment_type_id,
    employer_name = lp.employer_name,
    monthly_income = lp.monthly_income,
    source_of_funds = lp.source_of_funds
FROM public.lender_profiles lp
WHERE l.lender_id = lp.id
  AND l.employment_type IS NULL
  AND lp.employment_type IS NOT NULL;

UPDATE public.loans l
SET employment_type_id = et.id
FROM public.employment_types et
WHERE l.employment_type_id IS NULL
  AND l.employment_type = et.code;

-- Backfill loan_emergency_contacts from legacy per-lender emergency_contacts.
-- Fan-out: every loan of a lender gets a copy of that lender's contacts
-- (dedupe by loan_id+phone via ON CONFLICT DO NOTHING).
INSERT INTO public.loan_emergency_contacts (loan_id, name, relationship, relationship_id, phone_number, address)
SELECT l.id, ec.name, ec.relationship, ec.relationship_id, ec.phone_number, ec.address
FROM public.loans l
JOIN public.emergency_contacts ec ON ec.lender_id = l.lender_id
ON CONFLICT (loan_id, phone_number) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- 4) Sync triggers — keep varchar code <-> uuid id in sync (00110 pattern)
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION sync_loans_lookup_ids()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.payment_frequency_id IS NOT NULL AND (NEW.payment_frequency IS NULL OR TG_OP='INSERT' OR NEW.payment_frequency_id IS DISTINCT FROM OLD.payment_frequency_id) THEN SELECT code INTO NEW.payment_frequency FROM public.payment_frequencies WHERE id=NEW.payment_frequency_id; ELSIF NEW.payment_frequency IS NOT NULL THEN SELECT id INTO NEW.payment_frequency_id FROM public.payment_frequencies WHERE code=NEW.payment_frequency; END IF;
  IF NEW.status_id IS NOT NULL AND (NEW.status IS NULL OR TG_OP='INSERT' OR NEW.status_id IS DISTINCT FROM OLD.status_id) THEN SELECT code INTO NEW.status FROM public.loan_statuses WHERE id=NEW.status_id; ELSIF NEW.status IS NOT NULL THEN SELECT id INTO NEW.status_id FROM public.loan_statuses WHERE code=NEW.status; END IF;
  -- NEW in 00128: employment_type snapshot on loans
  IF TG_OP='INSERT' OR NEW.employment_type_id IS DISTINCT FROM OLD.employment_type_id OR NEW.employment_type IS DISTINCT FROM OLD.employment_type THEN
    IF NEW.employment_type_id IS NOT NULL AND (NEW.employment_type IS NULL OR TG_OP='INSERT') THEN SELECT code INTO NEW.employment_type FROM public.employment_types WHERE id=NEW.employment_type_id;
    ELSIF NEW.employment_type IS NOT NULL THEN SELECT id INTO NEW.employment_type_id FROM public.employment_types WHERE code=NEW.employment_type; END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_loans_lookup ON public.loans;
CREATE TRIGGER trg_sync_loans_lookup BEFORE INSERT OR UPDATE ON public.loans FOR EACH ROW EXECUTE FUNCTION sync_loans_lookup_ids();

CREATE OR REPLACE FUNCTION sync_loan_emergency_lookup()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.relationship_id IS DISTINCT FROM OLD.relationship_id THEN
    SELECT code INTO NEW.relationship FROM public.relationship_types WHERE id=NEW.relationship_id;
  ELSIF NEW.relationship IS DISTINCT FROM OLD.relationship THEN
    SELECT id INTO NEW.relationship_id FROM public.relationship_types WHERE code=NEW.relationship;
  ELSIF TG_OP='INSERT' THEN
    IF NEW.relationship_id IS NOT NULL THEN SELECT code INTO NEW.relationship FROM public.relationship_types WHERE id=NEW.relationship_id;
    ELSIF NEW.relationship IS NOT NULL THEN SELECT id INTO NEW.relationship_id FROM public.relationship_types WHERE code=NEW.relationship;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_loan_emergency_lookup ON public.loan_emergency_contacts;
CREATE TRIGGER trg_sync_loan_emergency_lookup BEFORE INSERT OR UPDATE ON public.loan_emergency_contacts FOR EACH ROW EXECUTE FUNCTION sync_loan_emergency_lookup();

-- ─────────────────────────────────────────────────────────────────
-- 5) RLS + grants + realtime for loan_emergency_contacts
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE public.loan_emergency_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "loan_emergency_contacts_read" ON public.loan_emergency_contacts;
CREATE POLICY "loan_emergency_contacts_read" ON public.loan_emergency_contacts
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT auth_own_loan_ids())
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND loan_id IN (SELECT rider_assigned_loan_ids())
    )
  );

GRANT SELECT ON public.loan_emergency_contacts TO anon, authenticated;
GRANT ALL ON public.loan_emergency_contacts TO service_role;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='loan_emergency_contacts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.loan_emergency_contacts;
  END IF;
EXCEPTION WHEN OTHERS THEN RAISE WARNING 'realtime loan_emergency_contacts: %', SQLERRM;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- 6) Canonical view refresh — expose loan snapshot cleanly
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_loans_canonical AS
  SELECT
    l.id, l.loan_number, l.lender_id, l.in_office_application_id,
    l.principal_amount, l.interest_rate,
    l.payment_frequency_id, pf.code AS payment_frequency, pf.label AS payment_frequency_label,
    l.term_days, l.term_periods, l.installment_amount, l.purpose,
    l.status_id, ls.code AS status, ls.label AS status_label,
    l.employment_type_id, et.code AS employment_type, et.label AS employment_type_label,
    l.employer_name, l.monthly_income, l.source_of_funds,
    l.approved_by, l.rejected_by, l.rejection_reason,
    l.created_at, l.updated_at
  FROM public.loans l
  LEFT JOIN public.payment_frequencies pf ON pf.id = l.payment_frequency_id
  LEFT JOIN public.loan_statuses ls ON ls.id = l.status_id
  LEFT JOIN public.employment_types et ON et.id = l.employment_type_id;
ALTER VIEW public.v_loans_canonical SET (security_invoker = true);
GRANT SELECT ON public.v_loans_canonical TO anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────
-- 7) Deprecation comments — lender_profiles keeps columns only for compat
-- ─────────────────────────────────────────────────────────────────
COMMENT ON COLUMN public.lender_profiles.employment_type IS 'DEPRECATED (00128): moved to loans.employment_type per-loan snapshot. Do NOT read/write — kept only for zero-downtime compat. Will be dropped in v2.';
COMMENT ON COLUMN public.lender_profiles.employment_type_id IS 'DEPRECATED (00128): moved to loans.employment_type_id. Kept only for compat.';
COMMENT ON COLUMN public.lender_profiles.employer_name IS 'DEPRECATED (00128): moved to loans.employer_name per-loan snapshot. Do NOT use.';
COMMENT ON COLUMN public.lender_profiles.monthly_income IS 'DEPRECATED (00128): moved to loans.monthly_income per-loan snapshot. Do NOT use.';
COMMENT ON COLUMN public.lender_profiles.source_of_funds IS 'DEPRECATED (00128): moved to loans.source_of_funds per-loan snapshot. Do NOT use.';
COMMENT ON TABLE public.emergency_contacts IS 'LEGACY per-lender contacts (00128): prefer loan_emergency_contacts (per-loan snapshot). New code must use loan_emergency_contacts; this table kept for history/compat.';
COMMENT ON COLUMN public.loans.employment_type IS 'Per-loan snapshot (00128 canonical: employment_type_id uuid). Source of truth for CI/approval — NOT lender_profiles.';
COMMENT ON COLUMN public.loans.employment_type_id IS 'Canonical FK -> employment_types.id (00128). Per-loan financial snapshot.';
COMMENT ON COLUMN public.loans.employer_name IS 'Per-loan snapshot (00128). Employer at application time.';
COMMENT ON COLUMN public.loans.monthly_income IS 'Per-loan snapshot (00128). Monthly income at application time.';
COMMENT ON COLUMN public.loans.source_of_funds IS 'Per-loan snapshot (00128).';
COMMENT ON TABLE public.loan_emergency_contacts IS 'Per-loan emergency contacts snapshot (00128). Source of truth for CI/approval — replaces per-lender emergency_contacts.';

-- v2 DROP path (DO NOT RUN until Flutter + Edge fully migrated):
-- ALTER TABLE public.lender_profiles DROP COLUMN employment_type;
-- ALTER TABLE public.lender_profiles DROP COLUMN employment_type_id;
-- ALTER TABLE public.lender_profiles DROP COLUMN employer_name;
-- ALTER TABLE public.lender_profiles DROP COLUMN monthly_income;
-- ALTER TABLE public.lender_profiles DROP COLUMN source_of_funds;
-- DROP TABLE public.emergency_contacts;

COMMIT;
