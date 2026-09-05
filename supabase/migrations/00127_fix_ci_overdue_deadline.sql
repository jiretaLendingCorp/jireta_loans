-- 00127_fix_ci_overdue_deadline.sql
-- BUG: expire_overdue_assignments() considered a CI overdue with
--   deadline < NOW()
-- `deadline` is a TIMESTAMPTZ set from the date picker, i.e. stored at the
-- START of the deadline day (midnight). So `deadline < NOW()` became true at
-- 00:00 on the deadline day itself — a CI assigned with deadline Sep 05 was
-- auto-expired at 12:00 AM Sep 05, before the rider had a single full day.
--
-- FIX: a CI is overdue only once the deadline DAY has fully passed, compared
-- in Asia/Manila (same convention as v_loan_schedules in 00120):
--   (deadline AT TIME ZONE 'Asia/Manila')::date < (now_manila())::date
--
-- Also repairs CI rows that were wrongly auto-expired while their deadline
-- day had not yet passed (deadline day >= today), restoring them to
-- 'assigned' so the rider still has the full deadline day. The repair is
-- guarded: it only touches CIs whose loan is still in a pre-completion CI
-- flow AND which have no other active CI on the same loan (so a reassignment
-- is never resurrected as a duplicate).

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Fixed expiry function (CI branch only; collections/disbursements
--    keep their existing 24h / 48h grace periods).
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
  -- Deadline is a date (stored at midnight of that day, Manila). The rider
  -- owns the ENTIRE deadline day, so a CI is overdue only once the deadline
  -- DATE is strictly before today's Manila date — never during the day.
  FOR r IN
    SELECT id, loan_id, rider_id, deadline
    FROM credit_investigations
    WHERE status IN ('assigned','accepted','in_progress')
      AND deadline IS NOT NULL
      AND (deadline AT TIME ZONE 'Asia/Manila')::date < (now_manila())::date
  LOOP
    UPDATE credit_investigations
      SET status = 'failed',
          notes = COALESCE(notes,'') || ' [auto-expired: deadline ' || (r.deadline AT TIME ZONE 'Asia/Manila')::text || ' passed]',
          updated_at = now_manila()
      WHERE id = r.id AND status IN ('assigned','accepted','in_progress');

    IF FOUND THEN
      v_ci := v_ci + 1;
      -- Notify rider that assignment is overdue and removed
      BEGIN
        INSERT INTO notifications (user_id, title, body, type, reference_id, is_read, sent_at)
        VALUES (
          r.rider_id,
          'CI Assignment Overdue — Removed',
          'Your CI assignment (deadline ' || to_char((r.deadline AT TIME ZONE 'Asia/Manila'), 'Mon DD, YYYY') || ') is overdue and has been removed from your tasks. Contact your manager if needed.',
          'ci_overdue',
          r.id,
          false,
          now_manila()
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
          updated_at = now_manila()
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
          now_manila()
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
          updated_at = now_manila()
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
          now_manila()
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'delivery overdue notification failed for %: %', r.id, SQLERRM;
      END;
    END IF;
  END LOOP;

  -- ── Free riders who now have zero active assignments ─────────────
  -- This restores is_available so HM/Employee can reassign them.
  UPDATE rider_profiles rp
    SET is_available = true, updated_at = now_manila()
    WHERE rp.is_available = false
      AND NOT rider_has_active_assignment(rp.id);

  RETURN QUERY SELECT v_ci, v_col, v_dis;
END;
$$;

COMMENT ON FUNCTION expire_overdue_assignments() IS
  'Marks overdue CI (deadline DAY < today Manila), collection (collection_schedule < NOW()-24h or due_date+3d), and rider_delivery (delivery_date < NOW()-48h) as failed, inserts overdue notifications for riders so assignment disappears from their active lists and they are notified. Called by pg_cron and by view edge functions on every rider list fetch for instant UX.';

-- ─────────────────────────────────────────────────────────────────────
-- 2) Repair wrongly auto-expired CI rows
--    Restores CIs that were failed by the old `deadline < NOW()` bug while
--    their deadline day had not yet passed. Guards:
--      - loan still in a pre-completion CI flow (pending/under_review/
--        ci_required/ci_assigned)
--      - no other ACTIVE CI exists on the same loan (never resurrect a
--        duplicate after a reassignment)
-- ─────────────────────────────────────────────────────────────────────
CREATE TEMP TABLE _restored_ci_ids ON COMMIT DROP AS
SELECT ci.id AS ci_id
FROM credit_investigations ci
JOIN loans l ON l.id = ci.loan_id
WHERE ci.status = 'failed'
  AND ci.notes LIKE '%[auto-expired: deadline%'
  AND (ci.deadline AT TIME ZONE 'Asia/Manila')::date >= (now_manila())::date
  AND l.status IN ('pending','under_review','ci_required','ci_assigned')
  AND NOT EXISTS (
    SELECT 1 FROM credit_investigations c2
    WHERE c2.loan_id = ci.loan_id
      AND c2.id <> ci.id
      AND c2.status IN ('assigned','accepted','in_progress')
  );

UPDATE credit_investigations ci
SET status = 'assigned',
    notes = trim(both ' ' FROM regexp_replace(COALESCE(ci.notes,''), '\[auto-expired: deadline [^\]]*\]', '', 'g'))
            || ' [restored: deadline day had not yet passed]',
    updated_at = now_manila()
FROM _restored_ci_ids r
WHERE ci.id = r.ci_id;

-- Re-sync availability for riders of restored CIs: after the restore they
-- hold an active assignment again, so they are busy unless they truly have
-- no active assignment (rider_has_active_assignment is computed live).
UPDATE rider_profiles rp
SET is_available = NOT rider_has_active_assignment(rp.id),
    updated_at = now_manila()
WHERE rp.id IN (
  SELECT DISTINCT ci.rider_id
  FROM credit_investigations ci
  JOIN _restored_ci_ids r ON r.ci_id = ci.id
);

DO $repair_notice$
BEGIN
  RAISE NOTICE 'Restored % wrongly auto-expired CI(s) to assigned', (SELECT COUNT(*) FROM _restored_ci_ids);
END $repair_notice$;

COMMIT;