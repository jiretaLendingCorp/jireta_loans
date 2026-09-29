-- supabase/migrations/00181_completed_collection_payments_verified.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- FIX: "collection completed pero HINDI nabawasan ang utang ng lender".
--
-- Bakit nangyayari: ang loan balance ay binibilang lang mula sa `verified` na
-- payments (`_shared/loan_financials.ts` + ang gate sa `v_loan_schedules`).
-- May mga koleksyong naka-`completed` na PERO `pending` pa ang bayad nila —
-- hindi sila binibilang, kaya hindi bumaba ang balance. Nangyayari ito kapag:
--   • ang lumang approval flow (na nilaktawan na ngayon) ang nag-iwan ng
--     `pending` na rider_collection payment, o
--   • ang 00180 ay nag-auto-complete ng lumang `pending_approval` na row na
--     `pending` pa ang payment.
--
-- Ang bagong `collections-manage?fn=upload-proof` ay nag-a-verify na ng nakitang
-- `pending` payment bago mag-`completed` (parehong fix sa code). Dito naman ang
-- mga LUMANG row.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- 0) Kung hindi pa na-apply ang 00180: ang lumang `pending_approval` ay hindi na
--    maa-approve (tinanggal na ang approve/reject) — i-finalize na bilang
--    `completed` para hindi maiwang nakabinbin.
UPDATE collection_assignments
SET status       = 'completed',
    completed_at = COALESCE(completed_at, NOW())
WHERE status = 'pending_approval';

-- 1) Ang `pending` na rider_collection payment ng isang `completed` na
--    koleksyon ay dapat `verified` — hawak na ng rider ang cash at naka-submit
--    na ang proof. Kapag hindi ito ma-verify, hindi ito binibilang sa balance.
UPDATE payments p
SET status  = 'verified',
    paid_at = COALESCE(p.paid_at, ca.completed_at, p.created_at)
FROM collection_assignments ca
WHERE ca.id = p.collection_assignment_id
  AND ca.status = 'completed'
  AND p.status = 'pending'
  AND p.payment_method = 'rider_collection';

-- 2) Ang `verified` na bayad na walang `paid_at` ay hindi lumalabas sa mga
--    monthly report / dashboard (naka-base sila sa `paid_at`).
UPDATE payments p
SET paid_at = COALESCE(ca.completed_at, p.created_at)
FROM collection_assignments ca
WHERE ca.id = p.collection_assignment_id
  AND ca.status = 'completed'
  AND p.status = 'verified'
  AND p.paid_at IS NULL;

-- 3) Report: `completed` na koleksyon na WALANG payment row — hindi ito basta
--    maaayos sa SQL dahil kailangan ng allocation sa installment ng loan.
--    Lalabas ang bilang sa `supabase db push` log para may mahanap na aayusin.
DO $$
DECLARE
  orphan_count integer;
BEGIN
  SELECT count(*) INTO orphan_count
  FROM collection_assignments ca
  WHERE ca.status = 'completed'
    AND ca.amount_collected IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM payments p WHERE p.collection_assignment_id = ca.id
    );

  IF orphan_count > 0 THEN
    RAISE NOTICE '% completed collection(s) na walang naka-link na payment row — kailangang i-record ang bayad para bumaba ang balance.', orphan_count;
  ELSE
    RAISE NOTICE 'Walang completed collection na walang linked payment. OK.';
  END IF;
END $$;

COMMIT;
