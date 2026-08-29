-- 00114_overdue_expiry_and_notifications.sql
-- Business rule:
--   Kapag nag-assign si HM/Employee kay rider (CI, Collections, Cash Delivery)
--   dapat ma-notify si rider (already done via ci-manage/collections-manage/
--   disbursements-delivery). Pag overdue na, dapat ma-notify ulit si rider
--   na overdue/expired na at mawawala na yung naka-assign sa kanya.
--   This migration adds:
--     - missing notification_types for overdue expiries
--     - missing CI status 'failed' (collections/disbursements already have it)
--     - DB function expire_overdue_assignments() that marks overdue CI/
--       collection/delivery as failed, frees rider, and inserts overdue
--       notifications for the rider — so the assignment disappears from rider
--       lists (which filter on assigned/accepted/in_progress/pending) and rider
--       sees a push/in-app notification.
--     - pg_cron schedule (best-effort, guarded) + trigger on loan overdue.
--     - helper to free riders who have no other active assignments.

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Seed overdue notification types (idempotent)
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO notification_types (code, label, sort_order) VALUES
  ('ci_overdue',           'CI Overdue',            30),
  ('collection_overdue',   'Collection Overdue',    31),
  ('disbursement_overdue', 'Disbursement Overdue',  32),
  ('assignment_expired',   'Assignment Expired',    33)
ON CONFLICT (code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────
-- 2) Ensure CI has 'failed' status (collections/disbursements already do)
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO credit_investigation_statuses (code, label, sort_order) VALUES
  ('failed', 'Failed', 6)
ON CONFLICT (code) DO NOTHING;

-- Also add generic 'expired' as alias for clarity if teams filter by it.
-- Keep 'failed' as canonical overdue-expired state; 'expired' is just an
-- extra synonym so expired rows show a distinct label if queried.
INSERT INTO collection_assignment_statuses (code, label, sort_order) VALUES
  ('expired', 'Expired', 7)
ON CONFLICT (code) DO NOTHING;

INSERT INTO disbursement_statuses (code, label, sort_order) VALUES
  ('expired', 'Expired', 5)
ON CONFLICT (code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Helper: does rider still hold an active assignment?
--    Active = collection assigned/accepted, CI assigned/accepted/in_progress,
--             disbursement pending (rider_delivery)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rider_has_active_assignment(p_rider_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM collection_assignments
    WHERE rider_id = p_rider_id AND status IN ('assigned','accepted')
  ) OR EXISTS (
    SELECT 1 FROM credit_investigations
    WHERE rider_id = p_rider_id AND status IN ('assigned','accepted','in_progress')
  ) OR EXISTS (
    SELECT 1 FROM disbursements
    WHERE rider_id = p_rider_id AND method = 'rider_delivery' AND status = 'pending'
  );
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 4) Main expiry function: marks overdue rows as failed, inserts
--    notifications for riders, and frees riders with no remaining active
--    assignments. Idempotent — re-running changes nothing if already failed.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION expire_overdue_assignments()
RETURNS TABLE (
  expired_ci INT,
  expired_collections INT,
  expired_disbursements INT
) LANGUAGE plpgsql AS $$
DECLARE
  v_ci INT := 0;
  v_col INT := 0;
  v_dis INT := 0;
  r RECORD;
BEGIN
  -- ── CI overdue ────────────────────────────────────────────────────
  -- deadline passed while still pending work (assigned/accepted/in_progress).
  -- Grace: 0 — deadline is the contract. Use deadline < NOW().
  FOR r IN
    SELECT id, loan_id, rider_id, deadline
    FROM credit_investigations
    WHERE status IN ('assigned','accepted','in_progress')
      AND deadline IS NOT NULL
      AND deadline < NOW()
  LOOP
    UPDATE credit_investigations
      SET status = 'failed',
          notes = COALESCE(notes,'') || ' [auto-expired: deadline ' || r.deadline::text || ' passed]',
          updated_at = NOW()
      WHERE id = r.id AND status IN ('assigned','accepted','in_progress');

    IF FOUND THEN
      v_ci := v_ci + 1;
      -- Notify rider that assignment is overdue and removed
      BEGIN
        INSERT INTO notifications (user_id, title, body, type, reference_id, is_read, sent_at)
        VALUES (
          r.rider_id,
          'CI Assignment Overdue — Removed',
          'Your CI assignment (deadline ' || to_char(r.deadline, 'Mon DD, YYYY') || ') is overdue and has been removed from your tasks. Contact your manager if needed.',
          'ci_overdue',
          r.id,
          false,
          NOW()
        );
      EXCEPTION WHEN OTHERS THEN
        -- Never fail the whole batch because a single notification insert fails
        RAISE WARNING 'ci overdue notification failed for %: %', r.id, SQLERRM;
      END;
    END IF;
  END LOOP;

  -- ── Collection overdue ────────────────────────────────────────────
  -- If collection_schedule exists, use it; otherwise fall back to loan
  -- schedule due_date + 3 days grace (office gives rider a few days to
  -- collect after due date before considering it abandoned).
  FOR r IN
    SELECT ca.id, ca.rider_id, ca.collection_schedule, ca.loan_schedule_id,
           ls.due_date, ls.loan_id
    FROM collection_assignments ca
    JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
    WHERE ca.status IN ('assigned','accepted')
      AND ca.rider_id IS NOT NULL
      AND (
        -- Has an explicit collection schedule that is past
        (ca.collection_schedule IS NOT NULL AND ca.collection_schedule < NOW() - INTERVAL '24 hours')
        OR
        -- No schedule but loan installment due date is > 3 days past
        (ca.collection_schedule IS NULL AND ls.due_date < CURRENT_DATE - INTERVAL '3 days')
      )
  LOOP
    UPDATE collection_assignments
      SET status = 'failed',
          collection_notes = COALESCE(collection_notes,'') || ' [auto-expired: overdue]',
          updated_at = NOW()
      WHERE id = r.id AND status IN ('assigned','accepted');

    IF FOUND THEN
      v_col := v_col + 1;
      BEGIN
        INSERT INTO notifications (user_id, title, body, type, reference_id, is_read, sent_at)
        VALUES (
          r.rider_id,
          'Collection Assignment Overdue — Removed',
          'Your collection assignment (due ' || COALESCE(r.collection_schedule::date::text, r.due_date::text) || ') is overdue and has been removed from your tasks.',
          'collection_overdue',
          r.id,
          false,
          NOW()
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'collection overdue notification failed for %: %', r.id, SQLERRM;
      END;
    END IF;
  END LOOP;

  -- ── Cash delivery overdue (rider_delivery disbursements) ──────────
  -- delivery_date passed + 48h grace. Status pending only (not yet delivered).
  FOR r IN
    SELECT id, rider_id, delivery_date, loan_id, amount
    FROM disbursements
    WHERE method = 'rider_delivery'
      AND status = 'pending'
      AND rider_id IS NOT NULL
      AND delivery_date IS NOT NULL
      AND delivery_date < NOW() - INTERVAL '48 hours'
  LOOP
    UPDATE disbursements
      SET status = 'failed',
          delivery_notes = COALESCE(delivery_notes,'') || ' [auto-expired: delivery overdue]',
          updated_at = NOW()
      WHERE id = r.id AND status = 'pending';

    IF FOUND THEN
      v_dis := v_dis + 1;
      BEGIN
        INSERT INTO notifications (user_id, title, body, type, reference_id, is_read, sent_at)
        VALUES (
          r.rider_id,
          'Cash Delivery Overdue — Removed',
          'Your cash delivery for ₱' || r.amount::text || ' (scheduled ' || to_char(r.delivery_date, 'Mon DD, YYYY') || ') is overdue and has been removed.',
          'disbursement_overdue',
          r.id,
          false,
          NOW()
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'delivery overdue notification failed for %: %', r.id, SQLERRM;
      END;
    END IF;
  END LOOP;

  -- ── Free riders who now have zero active assignments ─────────────
  -- This restores is_available so HM/Employee can reassign them.
  UPDATE rider_profiles rp
    SET is_available = true, updated_at = NOW()
    WHERE rp.is_available = false
      AND NOT rider_has_active_assignment(rp.id);

  RETURN QUERY SELECT v_ci, v_col, v_dis;
END;
$$;

COMMENT ON FUNCTION expire_overdue_assignments() IS
  'Marks overdue CI (deadline < NOW), collection (collection_schedule < NOW()-24h or due_date+3d), and rider_delivery (delivery_date < NOW()-48h) as failed, inserts overdue notifications for riders so assignment disappears from their active lists and they are notified. Called by pg_cron and by view edge functions on every rider list fetch for instant UX.';

-- ─────────────────────────────────────────────────────────────────────
-- 5) Extend auto_mark_overdue_loans to also trigger assignment expiry
--    When a loan flips to overdue, its collections are already stale — expire
--    them in the same call so rider sees removal atomically.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION auto_mark_overdue_loans()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- Original loan overdue marking (active -> overdue when schedule 30d past due with no payment)
  UPDATE loans
  SET status = 'overdue'
  WHERE status = 'active'
    AND id IN (
      SELECT ls.loan_id
      FROM loan_schedules ls
      LEFT JOIN payments p ON p.loan_schedule_id = ls.id AND p.status = 'verified'
      WHERE ls.due_date < (NOW() - INTERVAL '30 days')::date
      GROUP BY ls.loan_id, ls.id
      HAVING COALESCE(SUM(p.amount), 0) = 0
    );

  -- Immediately expire any rider assignments whose loan just went overdue
  -- (redundant with expire_overdue_assignments but keeps the two in sync)
  PERFORM * FROM expire_overdue_assignments();
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 6) pg_cron schedule — best effort. If pg_cron is not available (local dev
--    or hosted without cron), the DO block swallows the error; the view
--    edge functions still call expire_overdue_assignments() on every read.
--    Supabase hosts pg_cron in schema `cron` (with extension `pg_cron`);
--    local dev may use `extensions` — handle both.
-- ─────────────────────────────────────────────────────────────────────
DO $cron_do$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron extension not available — skipping cron schedule (edge functions will still expire on read)';
    RETURN;
  END;

  -- Ensure cron schema exists before scheduling
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    RAISE NOTICE 'cron schema not present — skipping pg_cron schedule (edge functions will still expire)';
    RETURN;
  END IF;

  -- Idempotent: unschedule old job if exists, then schedule fresh
  BEGIN
    PERFORM cron.unschedule('expire_overdue_assignments_every_10m');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  PERFORM cron.schedule(
    'expire_overdue_assignments_every_10m',
    '*/10 * * * *',
    $cron_job$ SELECT * FROM public.expire_overdue_assignments(); $cron_job$
  );

  RAISE NOTICE 'pg_cron job expire_overdue_assignments_every_10m scheduled every 10 minutes';

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Could not schedule pg_cron job (non-fatal, edge functions will still expire): %', SQLERRM;
END $cron_do$;

COMMIT;
