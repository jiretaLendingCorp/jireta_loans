-- supabase/migrations/00182_collection_auto_complete_trigger.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- DB-LEVEL ENFORCEMENT ng bagong business rule:
--   "Kapag na-collect na ng rider ang pera at nai-submit ang proof, COLLECTED
--    (completed) NA AGAD ang koleksyon — walang approval ng HM/Employee, at
--    agad bumababa ang loan balance."
--
-- BAKIT TRIGGER: ang rule ay dati lang nasa `collections-manage` Edge Function.
-- Kapag luma pa ang naka-deploy na function (o may ibang path na nagse-set ng
-- `pending_approval`), bumabalik ang lumang ugali: naka-`pending_approval` ang
-- koleksyon, hindi counted ang bayad (`verified` lang ang binibilang, at may
-- gate sa `v_loan_schedules`/`loan_financials`), kaya "completed/pending pero
-- HINDI nabawasan ang utang ng lender".
--
-- Sa trigger na ito, ang DATABASE mismo ang nagsisiguro:
--   1) `pending_approval` → `completed` (+ `completed_at`) — kahit anong code
--      version ang magsulat nito.
--   2) Ang `pending` na rider_collection payment ng isang completed na
--      koleksyon ay ginagawang `verified` (+ `paid_at`) — para BUMABA ang
--      balance sa parehong sandali (verified lang ang binibilang).
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- 1) Data fix (idempotent, kapareho ng 00181): ayusin ang mga lumang row na
--    hindi pa naisama ng naunang migration.
UPDATE collection_assignments
SET status       = 'completed',
    completed_at = COALESCE(completed_at, NOW())
WHERE status = 'pending_approval';

UPDATE payments p
SET status  = 'verified',
    paid_at = COALESCE(p.paid_at, ca.completed_at, p.created_at)
FROM collection_assignments ca
WHERE ca.id = p.collection_assignment_id
  AND ca.status = 'completed'
  AND p.status = 'pending'
  AND p.payment_method = 'rider_collection';

-- 2) BEFORE INSERT/UPDATE — bawal nang maiwan sa `pending_approval`.
CREATE OR REPLACE FUNCTION auto_complete_rider_collection() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'pending_approval' THEN
    NEW.status := 'completed';
    NEW.completed_at := COALESCE(NEW.completed_at, NOW());
  END IF;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION auto_complete_rider_collection() IS
  'Business rule: rider submission = completed agad (walang HM/Employee approval). Ang pending_approval ay isinasalin sa completed + completed_at.';

DROP TRIGGER IF EXISTS trg_auto_complete_rider_collection ON public.collection_assignments;
CREATE TRIGGER trg_auto_complete_rider_collection
  BEFORE INSERT OR UPDATE ON public.collection_assignments
  FOR EACH ROW EXECUTE FUNCTION auto_complete_rider_collection();

-- 3) AFTER INSERT/UPDATE — kapag `completed` na, i-verify ang rider payment
--    para mabilang agad sa loan balance (kung hindi, may koleksyong completed
--    na hindi bumaba ang utang).
CREATE OR REPLACE FUNCTION verify_completed_collection_payments() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'completed' THEN
    UPDATE payments
    SET status  = 'verified',
        paid_at = COALESCE(paid_at, NEW.completed_at, NOW())
    WHERE collection_assignment_id = NEW.id
      AND status = 'pending'
      AND payment_method = 'rider_collection';
  END IF;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION verify_completed_collection_payments() IS
  'Kapag completed ang koleksyon, ang pending na rider_collection payment nito ay ginagawang verified (+ paid_at) para counted agad sa loan balance.';

DROP TRIGGER IF EXISTS trg_verify_completed_collection_payments ON public.collection_assignments;
CREATE TRIGGER trg_verify_completed_collection_payments
  AFTER INSERT OR UPDATE ON public.collection_assignments
  FOR EACH ROW EXECUTE FUNCTION verify_completed_collection_payments();

-- 4) Report sa `db push` log kung may completed na koleksyong WALANG payment
--    row — kailangang i-record ang bayad para bumaba ang balance (hindi ito
--    basta maaayos sa SQL dahil kailangan ng allocation sa installment).
DO $$
DECLARE
  orphan_count integer;
BEGIN
  SELECT count(*) INTO orphan_count
  FROM collection_assignments ca
  WHERE ca.status = 'completed'
    AND ca.amount_collected IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.collection_assignment_id = ca.id);

  IF orphan_count > 0 THEN
    RAISE NOTICE '% completed collection(s) na walang linked payment — i-record ang bayad para bumaba ang balance.', orphan_count;
  ELSE
    RAISE NOTICE 'OK: lahat ng completed collection ay may linked payment.';
  END IF;
END $$;

COMMIT;
