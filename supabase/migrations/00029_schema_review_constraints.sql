-- supabase/migrations/00029_schema_review_constraints.sql
--
-- Schema-review hardening (applied to the linked project):
--   1) Payments must always carry loan context: a payment row needs either a
--      loan_schedule_id OR a collection_assignment_id so no payment can ever be
--      recorded without an auditable link back to a loan.
--   2) One primary address per user (addresses).
--   3) One primary address per in-office application (application_addresses).

DO $$
BEGIN
  -- 1) Payments context check
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'payments_context_check'
      AND conrelid = 'public.payments'::regclass
  ) THEN
    ALTER TABLE public.payments
      ADD CONSTRAINT payments_context_check
      CHECK (loan_schedule_id IS NOT NULL OR collection_assignment_id IS NOT NULL);
    RAISE NOTICE '00029: added payments_context_check';
  ELSE
    RAISE NOTICE '00029: payments_context_check already exists – skipping';
  END IF;

  -- 2) One primary address per user
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE indexname = 'idx_addresses_one_primary'
  ) THEN
    CREATE UNIQUE INDEX idx_addresses_one_primary
      ON public.addresses (user_id) WHERE is_primary;
    RAISE NOTICE '00029: created idx_addresses_one_primary';
  ELSE
    RAISE NOTICE '00029: idx_addresses_one_primary already exists – skipping';
  END IF;

  -- 3) One primary address per in-office application
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE indexname = 'idx_application_addresses_one_primary'
  ) THEN
    CREATE UNIQUE INDEX idx_application_addresses_one_primary
      ON public.application_addresses (application_id) WHERE is_primary;
    RAISE NOTICE '00029: created idx_application_addresses_one_primary';
  ELSE
    RAISE NOTICE '00029: idx_application_addresses_one_primary already exists – skipping';
  END IF;
END
$$;
