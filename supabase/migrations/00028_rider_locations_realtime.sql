-- 00028_rider_locations_realtime.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Live rider location tracking for the lender home screen.
--
-- 1) Publish `rider_locations` on the `supabase_realtime` publication so the
--    lender app receives location updates as soon as the rider posts them
--    (riders already push every ~30s via `location-manage?fn=update-rider`).
-- 2) Set REPLICA IDENTITY FULL so realtime can deliver the row payload to the
--    client even though `rider_locations` is protected by RLS.
-- 3) Extend the `rider_locations_read` SELECT policy so a lender can also read
--    (and therefore receive realtime events for) riders with ACCEPTED credit
--    investigation assignments or IN-FLIGHT rider-delivery disbursements on
--    their loans — not just accepted collection assignments.
--
-- Business rule: a rider's live location is only visible to the lender after
-- the rider has ACCEPTED the assignment (collection / CI) or is actively
-- delivering a loan disbursement (method=rider_delivery AND status=pending).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER PUBLICATION supabase_realtime ADD TABLE public.rider_locations;

ALTER TABLE public.rider_locations REPLICA IDENTITY FULL;

DROP POLICY IF EXISTS "rider_locations_read" ON public.rider_locations;

CREATE POLICY "rider_locations_read" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      -- Collection: rider accepted (or is working on) a collection assignment
      -- on one of the lender's loans.
      auth_role() = 'lender'
      AND EXISTS (
        SELECT 1
        FROM collection_assignments ca
        JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
        JOIN loans l ON l.id = ls.loan_id
        WHERE ca.rider_id = rider_locations.rider_id
          AND l.lender_id = auth.uid()
          AND ca.status IN ('accepted','in_progress')
      )
    )
    OR (
      -- Credit Investigation: rider accepted (or is working on) a CI on one of
      -- the lender's loans.
      auth_role() = 'lender'
      AND EXISTS (
        SELECT 1
        FROM credit_investigations ci
        JOIN loans l ON l.id = ci.loan_id
        WHERE ci.rider_id = rider_locations.rider_id
          AND l.lender_id = auth.uid()
          AND ci.status IN ('accepted','in_progress')
      )
    )
    OR (
      -- Disbursement / delivery: a rider-delivery disbursement is in flight
      -- (status=pending) for one of the lender's loans.
      auth_role() = 'lender'
      AND EXISTS (
        SELECT 1
        FROM disbursements d
        JOIN loans l ON l.id = d.loan_id
        WHERE d.rider_id = rider_locations.rider_id
          AND l.lender_id = auth.uid()
          AND d.method = 'rider_delivery'
          AND d.status = 'pending'
      )
    )
  );