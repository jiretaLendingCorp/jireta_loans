-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00166_office_cash_release_status.sql
-- Purpose   : PENDING pa rin ang Office Cash release sa Disbursements
--             kahit ACTIVE na ang loan at natanggap na ng lender ang cash.
--
-- ROOT CAUSE
--   • Ang `disbursements.status_id` ay may DEFAULT na uuid ng 'pending'
--     (00110 §9 "Defaults for new uuid columns").
--   • Ang BEFORE INSERT/UPDATE trigger `sync_disbursements_lookup_ids`
--     (00111) ay:
--         IF NEW.status_id IS DISTINCT FROM OLD.status_id THEN
--           SELECT code INTO NEW.status FROM disbursement_statuses
--            WHERE id = NEW.status_id;
--     Sa INSERT, `OLD.status_id` = NULL at `NEW.status_id` = DEFAULT
--     ('pending' uuid) → DISTINCT → kaya ang `status: 'completed'` na
--     ipinapadala ng `disbursements-delivery?fn=office-cash` ay
--     na-o-overwrite pabalik sa 'pending'.
--     HINDI naapektuhan ang `method` (walang default ang `method_id`),
--     kaya "Office Cash" ang Method habang "Pending" ang Status — at dahil
--     hiwalay na query ang pag-activate ng loan, nagiging ACTIVE ito kahit
--     pending ang disbursement row.
--
-- FIX (app side — kasama sa parehong commit)
--   `status_id: null` sa INSERT ng `disbursements` (office-cash,
--   rider-delivery, gcash) → ang ELSE branch (code → id) ang tatakbo, kaya
--   ang `status` code ang nananaig. Kapareho ng naunang fix sa `payments`
--   (`payments-manage` ay may `status_id: null`).
--
-- MIGRATION (data repair + defense)
--   1) Inaayos ang mga naunang row: pending na `office_cash` disbursement
--      na released na ang loan (active/overdue/completed) → completed.
--   2) Trigger: sa tuwing magiging released ang loan, awtomatikong
--      kino-complete ang pending na `office_cash` disbursement nito — kaya
--      kahit lumang deploy o manual na INSERT ang gumawa ng row, hindi na
--      ito maiiwang Pending.
--
-- Idempotent: safe na i-rerun.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Data repair — released na ang loan pero PENDING pa ang office cash
--    (hindi ginalaw ang `status_id`: ang trigger ang mag-sync nito mula sa
--     bagong `status` code — condition na `status IS DISTINCT FROM OLD.status`)
-- ─────────────────────────────────────────────────────────────────────
UPDATE public.disbursements d
   SET status = 'completed',
       disbursed_at = COALESCE(d.disbursed_at, d.created_at, now_manila()),
       updated_at = now_manila(),
       delivery_notes = COALESCE(d.delivery_notes, '') ||
         CASE
           WHEN COALESCE(d.delivery_notes, '') LIKE '%[auto-completed%' THEN ''
           ELSE ' [auto-completed: office cash already released]'
         END
  FROM public.loans l
 WHERE d.loan_id = l.id
   AND d.method = 'office_cash'
   AND d.status = 'pending'
   AND l.status IN ('active', 'overdue', 'completed');

-- ─────────────────────────────────────────────────────────────────────
-- 2) Defense — kapag naging released ang loan, i-complete ang pending na
--    office_cash row nito. Walang office_cash na pwedeng manatiling pending
--    habang active/overdue/completed na ang loan (business rule: ang office
--    cash ay ibinibigay nang harapan, kasabay ng pag-activate ng loan).
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION complete_office_cash_on_loan_release()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('active', 'overdue', 'completed')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    UPDATE public.disbursements
       SET status = 'completed',
           disbursed_at = COALESCE(disbursed_at, now_manila()),
           updated_at = now_manila(),
           delivery_notes = COALESCE(delivery_notes, '') ||
             CASE
               WHEN COALESCE(delivery_notes, '') LIKE '%[auto-completed%' THEN ''
               ELSE ' [auto-completed: office cash released with loan]'
             END
     WHERE loan_id = NEW.id
       AND method = 'office_cash'
       AND status = 'pending';
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION complete_office_cash_on_loan_release() IS
  $cmt$Kinukumpleto ang pending na office_cash disbursement kapag naging active/overdue/completed ang loan — dahilan: ang DEFAULT (pending) na disbursements.status_id kasama ng sync trigger ay nag-o-overwrite ng status: completed sa INSERT (tingnan ang 00166).$cmt$;

DROP TRIGGER IF EXISTS trg_office_cash_release_sync ON public.loans;
CREATE TRIGGER trg_office_cash_release_sync
  AFTER UPDATE OF status ON public.loans
  FOR EACH ROW
  EXECUTE FUNCTION complete_office_cash_on_loan_release();

COMMIT;
