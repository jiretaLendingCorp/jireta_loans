-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00179_loan_permanent_reject.sql
-- Purpose   : PERMANENT REJECT ng loan application.
--
--   Sa reject modal ng HM / Employee (00176), pinipili ng staff kung kailan
--   pwedeng mag-apply ulit ang lender. Idinagdag dito ang "Permanent reject"
--   na opsyon — kapag ito ang pinili, HINDI NA makakapag-apply muli ang
--   lender kahit kailan. Hindi na cooldown ang hadlang kundi ang flag mismo.
--
--   Semantics:
--     loans.permanently_rejected = true  → naka-block ang anumang bagong
--                                          application (`loans-apply` →
--                                          PERMANENTLY_REJECTED), kahit gaano
--                                          na katagal ang lumipas.
--     loans.permanently_rejected = false → dating takbo: ang 00176 na
--                                          `reapply_allowed_at` ang basehan.
--
--   Ang pag-unblock ay MANU-MANONG (staff / SQL) — sadyang walang UI para
--   dito, dahil ang permanenteng rejection ay para sa malubhang kaso (hal.
--   paulit-ulit na pekeng dokumento) at hindi dapat basta-basta maibalik.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

ALTER TABLE loans
  ADD COLUMN IF NOT EXISTS permanently_rejected BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN loans.permanently_rejected IS
  'Permanenteng rejection (desisyon ng staff sa reject modal). Kapag true, hindi na makakapag-apply ng bagong loan ang lender — hindi na ang reapply_allowed_at cooldown ang basehan. Pag-unblock: manu-mano (staff/SQL).';

-- Mabilis na paghahanap ng permanenteng na-reject na loan ng isang lender —
-- ito ang tinitignan ng `loans-apply` bago payagan ang bagong application.
CREATE INDEX IF NOT EXISTS idx_loans_lender_permanently_rejected
  ON loans (lender_id)
  WHERE permanently_rejected;

COMMIT;
