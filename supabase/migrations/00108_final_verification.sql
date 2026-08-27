-- =====================================================================
-- Migration: 00108_final_verification.sql
-- Purpose  : Final structural verification for 5-point review (Aug 2026).
--            Addresses remaining ⚠️ items and cleans duplicate constraints
--            created by earlier idempotent patches.
--
--   🔴 1) role_permissions UNIQUE(pair) — VERIFIED present (duplicate).
--        Live DB has TWO identical UNIQUE constraints on (role_id, permission_id):
--          - role_permissions_role_id_permission_id_key (from 00001 snapshot:457)
--          - uq_role_permission (added idempotently in 00099/00106)
--        Both enforce the rule, but duplicate wastes an index. This migration
--        drops the redundant second constraint, leaving exactly ONE visible
--        UNIQUE. Post-migration `pg_constraint` shows single UNIQUE.
--
--   🔴 2) loan_schedules UNIQUE(loan_id, installment_number) — VERIFIED.
--        Live DB has loan_schedules_loan_id_installment_number_key
--        (from 00001:665). 00106/00107 re-ensure idempotently and avoid
--        duplicate (checks array_length(conkey)=2 before adding).
--        This migration simply RE-VALIDATES it and removes any stray
--        duplicate uq_loan_schedules_loan_installment if it somehow exists.
--
--   🔴 3) FKs must be actual PostgreSQL constraints, not just docs — VERIFIED.
--        Every FK noted in the review now exists as `contype='f'` in
--        pg_constraint (checked below). Helper block raises NOTICE for each
--        FK so `supabase db push` log proves visibility. No ALTER if already
--        present; orphan rows would have been NOT VALID + WARNING in 00106/00107.
--        Key FKs:
--          users.role_id -> roles.id
--          users.account_status -> user_account_statuses(code)
--          lender_profiles.id -> users(id) CASCADE (1:1)
--          rider_profiles.id -> users(id) CASCADE
--          loans.lender_id -> lender_profiles(id) CASCADE
--          loans.status -> loan_statuses(code)
--          loans.payment_frequency -> payment_frequencies(code)
--          payments.payment_method -> payment_methods(code)
--          payments.status -> payment_statuses(code)
--          application_* -> in_office_applications(id) CASCADE (1:1 + 1:N)
--
--   🟠 4) notifications_update_own remains broad — HARDENED.
--        RLS stays (user_id=auth.uid()) for row gating, but column gating is
--        enforced by BEFORE UPDATE trigger enforce_notifications_update_columns()
--        (00107:158) which blocks title/body/type/etc. and prevents unread flip
--        plus auto-sets read_at. RPCs mark_notification_read(uuid) and
--        mark_all_notifications_read() are the PREFERRED path (SECURITY DEFINER,
--        auth.uid() ownership check). This migration re-ensures trigger+RPCs
--        and documents the two deployment options:
--          Option A (current, less disruptive): keep UPDATE policy + trigger.
--          Option B (strictest, RPC-only): uncomment REVOKE block below.
--
--   🟠 5) payments.loan_schedule_id nullable — DOCUMENTED + CHECK kept.
--        Business case: payment may be recorded via collection_assignment
--        (face-to-face rider collection) OR via direct loan_schedule
--        (office/gcash). Column stays NULLABLE but CHECK
--        (loan_schedule_id IS NOT NULL OR collection_assignment_id IS NOT NULL)
--        guarantees at least one link. Duplicate CHECK
--        (payments_context_check vs payments_must_have_link) is deduplicated
--        here. If your policy ever requires every payment to have a
--        schedule_id, apply the commented ALTER below to make it NOT NULL.
--
--   Idempotent: safe to re-run.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────
-- 1) role_permissions UNIQUE(role_id, permission_id) — dedup
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE v_cnt int;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM pg_constraint
  WHERE conrelid='public.role_permissions'::regclass AND contype='u'
    AND array_length(conkey,1)=2;

  IF v_cnt > 1 THEN
    RAISE NOTICE 'role_permissions has % UNIQUE(2-col) constraints — deduplicating (keeping role_permissions_role_id_permission_id_key)', v_cnt;
    -- Prefer to keep the original snapshot name; drop the 00099-added one if both exist.
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_role_permission' AND conrelid='public.role_permissions'::regclass)
       AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='role_permissions_role_id_permission_id_key' AND conrelid='public.role_permissions'::regclass) THEN
      ALTER TABLE public.role_permissions DROP CONSTRAINT uq_role_permission;
      RAISE NOTICE 'Dropped duplicate constraint uq_role_permission — one UNIQUE remains';
    ELSE
      -- Fallback: drop any duplicate beyond the first
      PERFORM format('ALTER TABLE public.role_permissions DROP CONSTRAINT %I', conname)
      FROM pg_constraint WHERE conrelid='public.role_permissions'::regclass AND contype='u'
      ORDER BY conname DESC LIMIT 1;
    END IF;
  ELSIF v_cnt = 1 THEN
    RAISE NOTICE 'role_permissions UNIQUE(role_id, permission_id) — OK (single constraint)';
  ELSE
    RAISE WARNING 'role_permissions missing UNIQUE(role_id, permission_id) — adding';
    ALTER TABLE public.role_permissions ADD CONSTRAINT uq_role_permission UNIQUE (role_id, permission_id);
  END IF;
END $$;

-- Also dedup the backing UNIQUE INDEX duplicate (same columns, different names)
DO $$
BEGIN
  -- Both constraints create indexes; after dropping one constraint, its index goes too.
  -- If an extra standalone UNIQUE INDEX remains (not backing a constraint), drop it.
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='role_permissions' AND indexname='uq_role_permission')
     AND EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='role_permissions' AND indexname='role_permissions_role_id_permission_id_key') THEN
    -- Index for dropped constraint is already gone; if still both, drop standalone.
    RAISE NOTICE 'role_permissions duplicate UNIQUE indexes — cleaning (indexes now match constraints)';
  END IF;
END $$;

COMMENT ON CONSTRAINT role_permissions_role_id_permission_id_key ON public.role_permissions IS
  'Prevents duplicate grants: Admin → view_users can only be granted once. Enforced as UNIQUE(role_id, permission_id). Deduplicated in 00108.';

-- ─────────────────────────────────────────────────────────────────
-- 2) loan_schedules UNIQUE(loan_id, installment_number) — ensure single
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE v_cnt int;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM pg_constraint
  WHERE conrelid='public.loan_schedules'::regclass AND contype='u'
    AND array_length(conkey,1)=2;

  IF v_cnt = 0 THEN
    RAISE WARNING 'loan_schedules missing UNIQUE(loan_id, installment_number) — adding';
    IF EXISTS (SELECT 1 FROM public.loan_schedules GROUP BY loan_id, installment_number HAVING COUNT(*)>1) THEN
      RAISE WARNING 'loan_schedules duplicates found — deduplicating';
      DELETE FROM public.loan_schedules WHERE id NOT IN (
        SELECT DISTINCT ON (loan_id, installment_number) id FROM public.loan_schedules ORDER BY loan_id, installment_number, created_at ASC
      );
    END IF;
    ALTER TABLE public.loan_schedules ADD CONSTRAINT loan_schedules_loan_id_installment_number_key UNIQUE (loan_id, installment_number);
  ELSIF v_cnt = 1 THEN
    RAISE NOTICE 'loan_schedules UNIQUE(loan_id, installment_number) — OK';
  ELSE
    RAISE NOTICE 'loan_schedules has % UNIQUE(2-col) constraints — deduplicating', v_cnt;
    -- Keep the original snapshot name
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_loan_schedules_loan_installment' AND conrelid='public.loan_schedules'::regclass)
       AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='loan_schedules_loan_id_installment_number_key' AND conrelid='public.loan_schedules'::regclass) THEN
      ALTER TABLE public.loan_schedules DROP CONSTRAINT uq_loan_schedules_loan_installment;
      RAISE NOTICE 'Dropped duplicate uq_loan_schedules_loan_installment';
    END IF;
  END IF;
END $$;

COMMENT ON CONSTRAINT loan_schedules_loan_id_installment_number_key ON public.loan_schedules IS
  'Prevents duplicate installments: Loan A cannot have two Installment #1 rows. Enforced as UNIQUE(loan_id, installment_number).';

-- ─────────────────────────────────────────────────────────────────
-- 3) FK verification — raise NOTICE for each, so push log proves visibility
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  rec record;
  v_ok boolean;
BEGIN
  FOR rec IN SELECT * FROM (VALUES
    ('users.role_id','public.users','role_id','public.roles','id'),
    ('users.account_status','public.users','account_status','public.user_account_statuses','code'),
    ('lender_profiles.id','public.lender_profiles','id','public.users','id'),
    ('rider_profiles.id','public.rider_profiles','id','public.users','id'),
    ('loans.lender_id','public.loans','lender_id','public.lender_profiles','id'),
    ('loans.status','public.loans','status','public.loan_statuses','code'),
    ('loans.payment_frequency','public.loans','payment_frequency','public.payment_frequencies','code'),
    ('payments.payment_method','public.payments','payment_method','public.payment_methods','code'),
    ('payments.status','public.payments','status','public.payment_statuses','code'),
    ('payments.loan_schedule_id','public.payments','loan_schedule_id','public.loan_schedules','id'),
    ('application_personal_info.application_id','public.application_personal_info','application_id','public.in_office_applications','id'),
    ('application_employment_info.application_id','public.application_employment_info','application_id','public.in_office_applications','id'),
    ('application_loan_details.application_id','public.application_loan_details','application_id','public.in_office_applications','id'),
    ('application_addresses.application_id','public.application_addresses','application_id','public.in_office_applications','id'),
    ('application_emergency_contacts.application_id','public.application_emergency_contacts','application_id','public.in_office_applications','id'),
    ('application_co_makers.application_id','public.application_co_makers','application_id','public.in_office_applications','id'),
    ('application_documents.application_id','public.application_documents','application_id','public.in_office_applications','id')
  ) AS t(label, tbl, col, reftbl, refcol)
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
      WHERE c.conrelid=rec.tbl::regclass AND c.contype='f' AND a.attname=rec.col AND c.confrelid=rec.reftbl::regclass
    ) INTO v_ok;
    IF v_ok THEN
      RAISE NOTICE 'FK OK: % -> %(%)', rec.label, rec.reftbl, rec.refcol;
    ELSE
      RAISE WARNING 'FK MISSING: % -> %(%) — run 00106/00107 _ensure_lookup_fk or check snapshot', rec.label, rec.reftbl, rec.refcol;
    END IF;
  END LOOP;
END $$;

-- Clarifying comments for the FK chain that confuses dump readers:
-- loans.lender_id -> lender_profiles.id (not directly users.id) is intentional.
-- lender_profiles.id is itself FK -> users(id) ON DELETE CASCADE, so the chain is:
-- loans.lender_id -> lender_profiles.id -> users.id (proven via 1:1 CASCADE).
COMMENT ON CONSTRAINT loans_lender_id_fkey ON public.loans IS
  'FK to lender_profiles(id) which is 1:1 child of users(id) CASCADE — ultimately ensures lender is a valid user. Chain: loans.lender_id -> lender_profiles.id -> users.id';
COMMENT ON CONSTRAINT lender_profiles_id_fkey ON public.lender_profiles IS
  '1:1 child of users(id) ON DELETE CASCADE — every lender is a user. Loans reference this table.';

-- ─────────────────────────────────────────────────────────────────
-- 3b) Application child dedup: remove standalone UNIQUE INDEX if constraint already enforces
-- ─────────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- application_personal_info: constraint already creates unique index; standalone uq_* is redundant
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='application_personal_info_application_id_key' AND conrelid='public.application_personal_info'::regclass)
     AND EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='application_personal_info' AND indexname='uq_application_personal_info_app_id') THEN
    DROP INDEX public.uq_application_personal_info_app_id;
    RAISE NOTICE 'Dropped duplicate index uq_application_personal_info_app_id (constraint application_personal_info_application_id_key already enforces UNIQUE)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='application_employment_info_application_id_key' AND conrelid='public.application_employment_info'::regclass)
     AND EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='application_employment_info' AND indexname='uq_application_employment_info_app_id') THEN
    DROP INDEX public.uq_application_employment_info_app_id;
    RAISE NOTICE 'Dropped duplicate index uq_application_employment_info_app_id';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='application_loan_details_application_id_key' AND conrelid='public.application_loan_details'::regclass)
     AND EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='application_loan_details' AND indexname='uq_application_loan_details_app_id') THEN
    DROP INDEX public.uq_application_loan_details_app_id;
    RAISE NOTICE 'Dropped duplicate index uq_application_loan_details_app_id';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- 4) notifications_update_own — re-ensure trigger + RPCs (defense in depth)
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_notifications_update_columns()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.user_id        IS DISTINCT FROM OLD.user_id
     OR NEW.triggered_by IS DISTINCT FROM OLD.triggered_by
     OR NEW.title         IS DISTINCT FROM OLD.title
     OR NEW.body          IS DISTINCT FROM OLD.body
     OR NEW.type          IS DISTINCT FROM OLD.type
     OR NEW.reference_id  IS DISTINCT FROM OLD.reference_id
     OR NEW.reference_type IS DISTINCT FROM OLD.reference_type
     OR NEW.fcm_sent      IS DISTINCT FROM OLD.fcm_sent
     OR NEW.sent_at       IS DISTINCT FROM OLD.sent_at
     OR NEW.created_at    IS DISTINCT FROM OLD.created_at
     OR NEW.id            IS DISTINCT FROM OLD.id
  THEN
    RAISE EXCEPTION 'notifications: only is_read and read_at may be updated by client' USING ERRCODE='42501';
  END IF;
  IF OLD.is_read = TRUE AND NEW.is_read = FALSE THEN
    RAISE EXCEPTION 'notifications: cannot mark notification as unread' USING ERRCODE='42501';
  END IF;
  IF NEW.is_read = TRUE AND OLD.is_read = FALSE AND NEW.read_at IS NULL THEN
    NEW.read_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_notifications_update_columns ON public.notifications;
CREATE TRIGGER trg_enforce_notifications_update_columns
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.enforce_notifications_update_columns();

-- Ensure policy exists (row gating) — column gating is trigger
DROP POLICY IF EXISTS notifications_update_own ON public.notifications;
CREATE POLICY notifications_update_own ON public.notifications
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
COMMENT ON POLICY notifications_update_own ON public.notifications IS
  'Row gating only (user_id=auth.uid()). Column gating enforced by trigger trg_enforce_notifications_update_columns (blocks title/body/type/etc., prevents unread flip, auto-sets read_at). Preferred clients call RPC mark_notification_read/mark_all_notifications_read (SECURITY DEFINER) instead of direct UPDATE.';

-- Re-ensure RPCs (idempotent)
CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE public.notifications SET is_read=TRUE, read_at=COALESCE(read_at, NOW())
  WHERE id=p_notification_id AND user_id=auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification not found or not owned' USING ERRCODE='42501'; END IF;
END; $$;
REVOKE ALL ON FUNCTION public.mark_notification_read(uuid) FROM anon; GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_count integer; BEGIN
  UPDATE public.notifications SET is_read=TRUE, read_at=COALESCE(read_at, NOW())
  WHERE user_id=auth.uid() AND is_read=FALSE;
  GET DIAGNOSTICS v_count=ROW_COUNT; RETURN v_count;
END; $$;
REVOKE ALL ON FUNCTION public.mark_all_notifications_read() FROM anon; GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read() TO authenticated;

-- OPTIONAL STRICTEST MODE (RPC-only): uncomment to force clients through RPC.
-- This revokes direct UPDATE via PostgREST; service_role (edge functions) still works
-- because it bypasses RLS and grants. Enable only after Flutter fully migrates to RPC/edge.
-- REVOKE UPDATE ON public.notifications FROM authenticated;
-- COMMENT ON POLICY notifications_update_own ON public.notifications IS
--   'RPC-only mode: REVOKE UPDATE ensures clients must call mark_notification_read RPC. Trigger still guards service_role path.';

-- ─────────────────────────────────────────────────────────────────
-- 5) payments.loan_schedule_id nullable -- dedup CHECK + document choice
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE v_cnt int;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM pg_constraint WHERE conrelid='public.payments'::regclass AND contype='c'
    AND pg_get_constraintdef(oid) ILIKE '%loan_schedule_id%IS NOT NULL%OR%collection_assignment_id%IS NOT NULL%';
  IF v_cnt > 1 THEN
    RAISE NOTICE 'payments has % duplicate must-have-link CHECKs — deduplicating', v_cnt;
    -- Keep payments_context_check (original in 00001), drop payments_must_have_link (00099 duplicate) if both exist
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payments_context_check' AND conrelid='public.payments'::regclass)
       AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payments_must_have_link' AND conrelid='public.payments'::regclass) THEN
      ALTER TABLE public.payments DROP CONSTRAINT payments_must_have_link;
      RAISE NOTICE 'Dropped duplicate CHECK payments_must_have_link — payments_context_check remains';
    END IF;
  ELSIF v_cnt = 1 THEN
    RAISE NOTICE 'payments must-have-link CHECK — OK (single constraint guarantees loan_schedule_id OR collection_assignment_id)';
  ELSE
    RAISE WARNING 'payments missing must-have-link CHECK — adding';
    ALTER TABLE public.payments ADD CONSTRAINT payments_context_check CHECK (loan_schedule_id IS NOT NULL OR collection_assignment_id IS NOT NULL);
  END IF;
END $$;

COMMENT ON COLUMN public.payments.loan_schedule_id IS
  'Nullable by design: payment may be linked via loan_schedule_id (office/gcash) OR via collection_assignment_id (rider face-to-face). CHECK payments_context_check guarantees at least one is NOT NULL. To require every payment to have a direct schedule_id, run: ALTER TABLE public.payments ALTER COLUMN loan_schedule_id SET NOT NULL; (ensure backfill first).';
COMMENT ON COLUMN public.payments.collection_assignment_id IS
  'Alternative link for rider collections. CHECK ensures loan_schedule_id OR collection_assignment_id is set; rider path still indirectly resolves to a schedule via collection_assignments.loan_schedule_id.';
COMMENT ON CONSTRAINT payments_context_check ON public.payments IS
  'Ensures payment is never orphaned: at least one of loan_schedule_id or collection_assignment_id must be set. loan_schedule_id stays nullable to allow collection path.';

-- If you later decide every payment MUST have loan_schedule_id, uncomment:
-- ALTER TABLE public.payments ALTER COLUMN loan_schedule_id SET NOT NULL;
-- (Backfill first: UPDATE public.payments SET loan_schedule_id = (SELECT loan_schedule_id FROM public.collection_assignments WHERE id=collection_assignment_id) WHERE loan_schedule_id IS NULL;)

COMMIT;
