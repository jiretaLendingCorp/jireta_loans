-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00191_account_upgrade_reject_window.sql
-- Purpose   : STAFF-DECIDED RESUBMIT WINDOW + PERMANENT REJECT PARA SA
--             ACCOUNT UPGRADE.
--
--   Dating hard-coded na 1 month (30 days) ang cooldown bago makapag-resubmit
--   ng Account Upgrade pagkatapos ma-reject. Ngayon, ang HM/Employee ang
--   pipili sa reject dialog kung kailan pwedeng mag-resubmit — Immediately,
--   1/3/6 months, exact date, o PERMANENTE nang hindi na makakapag-resubmit
--   (kapareho ng loan reject, 00176 / 00179).
--
--   Semantics:
--     account_upgrade_documents.reapply_allowed_at = oras/petsa kung kailan
--     PWEDE nang mag-resubmit ng Account Upgrade. Isang beses lang itong
--     naka-set — sa oras ng rejection mula sa reject dialog.
--       * timestamp sa future → naka-block pa (ACCOUNT_UPGRADE_COOLDOWN)
--       * timestamp sa nakaraan/ngayon → pwede nang mag-resubmit
--       * NULL → lumang behavior: 1 month mula sa reviewed_at
--              (backward-compatible sa lumang rejection at lumang app build)
--
--     lender_profiles.account_upgrade_permanently_rejected = TRUE kapag
--     "Permanent reject" ang pinili ng staff. Hindi na makakapag-submit ng
--     Account Upgrade ang lender kahit kailan (ACCOUNT_UPGRADE_PERMANENT);
--     hindi na cooldown date ang hadlang kundi ang flag mismo. Pag-unblock:
--     manu-mano (staff/SQL), pareho ng `loans.permanently_rejected`.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

ALTER TABLE account_upgrade_documents
  ADD COLUMN IF NOT EXISTS reapply_allowed_at TIMESTAMPTZ;

COMMENT ON COLUMN account_upgrade_documents.reapply_allowed_at IS
  'Staff-decided (HM/Employee sa reject dialog) na oras kung kailan pwedeng mag-resubmit ng Account Upgrade pagkatapos ng rejection. NULL = default 1-month cooldown mula sa reviewed_at.';

ALTER TABLE lender_profiles
  ADD COLUMN IF NOT EXISTS account_upgrade_permanently_rejected BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN lender_profiles.account_upgrade_permanently_rejected IS
  'Permanenteng rejection ng Account Upgrade (desisyon ng staff sa reject dialog). Kapag true, hindi na makakapag-resubmit ang lender — hindi na ang reapply_allowed_at cooldown ang basehan. Pag-unblock: manu-mano (staff/SQL).';

COMMIT;
