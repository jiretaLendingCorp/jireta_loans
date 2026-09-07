-- =====================================================================
-- Migration: 00130_in_office_personal_docs_and_loan_snapshot.sql
-- Purpose  : In-office (walk-in) wizard update per staff request (Tagalog):
--   • ADD to in-office: middle_name (already exists), suffix (NEW),
--     valid_id, selfie_with_id, mayors_permit, birth_certificate (uploadable).
--   • REMOVE from in-office: monthly_income + emergency_contact inputs.
--   • MOVE financial + emergency to loans table (per-loan snapshot, 00128
--     pattern): loans.monthly_income (+ employment snapshot) and
--     loan_emergency_contacts are the source of truth, NOT
--     application_employment_info.monthly_income /
--     application_emergency_contacts.
--
-- DESIGN — Additive, not destructive (zero-downtime, follows 00110/00128):
--   • ADD application_personal_info.suffix (VARCHAR 20, matches users.suffix).
--   • ENSURE document_types has selfie_with_id (+ mayors_permit /
--     birth_certificate / valid_id_back already added in 00124 — re-ensured
--     idempotently) so in-office Step 5 uploads never FK-fail.
--   • ENSURE loans snapshot columns + loan_emergency_contacts exist
--     (created in 00128 — re-ensured idempotently for fresh DBs that
--     may have skipped ordering).
--   • DO NOT DROP application_employment_info.monthly_income or
--     application_emergency_contacts yet: old drafts + old app versions
--     still write them. They are marked DEPRECATED; new Flutter + Edge
--     code stops reading/writing them. Next v2 migration may DROP after
--     full rollout.
--   • Backfill: copy any existing in-office monthly_income / emergency
--     snapshots onto their converted loans (loans.monthly_income +
--     loan_emergency_contacts) where the loan row is still NULL/empty,
--     so history is preserved in the loans table.
--
-- Idempotent: every DDL guarded by catalog checks.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─────────────────────────────────────────────────────────────────
-- 1) application_personal_info.suffix (matches users.suffix VARCHAR(20))
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE public.application_personal_info
  ADD COLUMN IF NOT EXISTS suffix VARCHAR(20);

-- ─────────────────────────────────────────────────────────────────
-- 2) document_types for in-office Step 5 uploads
--    Account Upgrade uses: valid_id (+valid_id_back), selfie (= selfie with ID),
--    mayors_permit, birth_certificate. In-office must accept the same set
--    plus an explicit selfie_with_id alias so either client code works.
-- ─────────────────────────────────────────────────────────────────
INSERT INTO public.document_types (code, label, sort_order)
SELECT v.code, v.label, v.sort_order
FROM (VALUES
  ('valid_id_back',    'Valid ID (Back)',    17),
  ('mayors_permit',    'Mayor''s Permit',     18),
  ('birth_certificate','Birth Certificate',  19),
  ('selfie_with_id',   'Selfie with ID',     20)
) AS v(code, label, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_types d WHERE d.code = v.code
);

-- Backfill uuid FK column for the new code (00110 pattern).
-- _add_uuid_fk_column equivalent inlined idempotently (function may not exist
-- on all environments, so guard with catalog checks instead of calling it).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='application_documents'
      AND column_name='document_type_id'
  ) THEN
    ALTER TABLE public.application_documents
      ADD COLUMN document_type_id UUID REFERENCES public.document_types(id);
  END IF;
END $$;

UPDATE public.application_documents ad
SET document_type_id = dt.id
FROM public.document_types dt
WHERE ad.document_type_id IS NULL AND ad.document_type = dt.code;

-- ─────────────────────────────────────────────────────────────────
-- 3) loans snapshot columns + loan_emergency_contacts (00128 re-ensure)
--    Fresh DBs apply migrations in order so these already exist; the
--    guards make this file safe to apply standalone.
-- ─────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='loans' AND column_name='employment_type') THEN
    ALTER TABLE public.loans ADD COLUMN employment_type VARCHAR(30) REFERENCES employment_types(code);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='loans' AND column_name='employment_type_id') THEN
    ALTER TABLE public.loans ADD COLUMN employment_type_id UUID REFERENCES employment_types(id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='loans' AND column_name='employer_name') THEN
    ALTER TABLE public.loans ADD COLUMN employer_name VARCHAR(255);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='loans' AND column_name='monthly_income') THEN
    ALTER TABLE public.loans ADD COLUMN monthly_income DECIMAL(12,2) CHECK (monthly_income >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='loans' AND column_name='source_of_funds') THEN
    ALTER TABLE public.loans ADD COLUMN source_of_funds VARCHAR(50);
  END IF;
END $$;

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
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_loan_emergency_loan_phone') THEN
    ALTER TABLE public.loan_emergency_contacts
      ADD CONSTRAINT uq_loan_emergency_loan_phone UNIQUE (loan_id, phone_number);
  END IF;
EXCEPTION WHEN OTHERS THEN RAISE WARNING 'uq_loan_emergency_loan_phone: %', SQLERRM;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- 4) Backfill: move existing in-office financial + emergency snapshots
--    onto their converted loans (only where loan is still empty).
-- ─────────────────────────────────────────────────────────────────
-- monthly_income / employment snapshot: application_employment_info -> loans
UPDATE public.loans l
SET employment_type = COALESCE(l.employment_type, aei.employment_type),
    employer_name   = COALESCE(l.employer_name, aei.employer_name),
    monthly_income  = COALESCE(l.monthly_income, aei.monthly_income)
FROM public.in_office_applications ioa
JOIN public.application_employment_info aei ON aei.application_id = ioa.id
WHERE l.in_office_application_id = ioa.id
  AND (l.monthly_income IS NULL OR l.employer_name IS NULL OR l.employment_type IS NULL)
  AND (aei.monthly_income IS NOT NULL OR aei.employer_name IS NOT NULL OR aei.employment_type IS NOT NULL);

-- emergency contacts: application_emergency_contacts -> loan_emergency_contacts
INSERT INTO public.loan_emergency_contacts (loan_id, name, relationship, phone_number, address)
SELECT l.id, aec.name, COALESCE(aec.relationship, 'Other'), aec.phone_number, aec.address
FROM public.loans l
JOIN public.application_emergency_contacts aec
  ON aec.application_id = l.in_office_application_id
WHERE l.in_office_application_id IS NOT NULL
  AND aec.name IS NOT NULL AND aec.phone_number IS NOT NULL
ON CONFLICT (loan_id, phone_number) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- 5) Deprecation comments — new code must NOT use the in-office copies
-- ─────────────────────────────────────────────────────────────────
COMMENT ON COLUMN public.application_employment_info.monthly_income IS 'DEPRECATED (00130): moved to loans.monthly_income per-loan snapshot. In-office wizard no longer collects this — kept only for old drafts/compat. Will be dropped in v2.';
COMMENT ON TABLE public.application_emergency_contacts IS 'DEPRECATED (00130): in-office wizard no longer collects emergency contacts. Per-loan source of truth is loan_emergency_contacts (see loans table). Kept for old drafts/compat; will be dropped in v2.';
COMMENT ON COLUMN public.application_personal_info.suffix IS 'In-office personal info suffix e.g. Jr., Sr., III (00130, mirrors users.suffix). Optional.';
COMMENT ON COLUMN public.application_personal_info.middle_name IS 'In-office personal info middle name (optional, mirrors users.middle_name).';

-- v2 DROP path (DO NOT RUN until Flutter + Edge fully migrated):
-- ALTER TABLE public.application_employment_info DROP COLUMN monthly_income;
-- DROP TABLE public.application_emergency_contacts;

COMMIT;
