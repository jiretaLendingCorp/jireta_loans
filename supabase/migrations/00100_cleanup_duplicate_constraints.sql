-- ============================================================
-- Migration: 00100_cleanup_duplicate_constraints.sql
-- Removes duplicate constraints introduced by 00099_schema_fixes.sql
-- All 4 constraints already existed with different names.
-- ============================================================

-- FIX 1: payments — drop duplicate CHECK (keep pre-existing payments_context_check)
ALTER TABLE public.payments
  DROP CONSTRAINT IF EXISTS payments_must_have_link;

-- FIX 2: role_permissions — drop duplicate UNIQUE (keep pre-existing role_permissions_role_id_permission_id_key)
ALTER TABLE public.role_permissions
  DROP CONSTRAINT IF EXISTS uq_role_permission;

-- FIX 3: loan_co_makers — drop duplicate UNIQUE (keep pre-existing loan_co_makers_loan_id_co_maker_id_key)
ALTER TABLE public.loan_co_makers
  DROP CONSTRAINT IF EXISTS uq_loan_co_maker;

-- ============================================================
-- FIX 4: in_office_applications — CONFLICTING wizard_step CHECKs
--
-- Pre-existing: in_office_applications_wizard_step_check = 1 to 5
-- Mine:         chk_wizard_step                          = 1 to 7
--
-- Both are enforced simultaneously → effective upper bound = 5
--
-- OPTION A: If your wizard has 5 steps → run this block:
ALTER TABLE public.in_office_applications
  DROP CONSTRAINT IF EXISTS chk_wizard_step;
-- Result: keeps original 1-5 constraint.

-- OPTION B: If your wizard has more than 5 steps (e.g. 6 or 7) → run this block instead:
-- ALTER TABLE public.in_office_applications
--   DROP CONSTRAINT IF EXISTS in_office_applications_wizard_step_check;
-- ALTER TABLE public.in_office_applications
--   DROP CONSTRAINT IF EXISTS chk_wizard_step;
-- ALTER TABLE public.in_office_applications
--   ADD CONSTRAINT chk_wizard_step CHECK (wizard_step BETWEEN 1 AND 7); -- adjust upper bound
-- ============================================================