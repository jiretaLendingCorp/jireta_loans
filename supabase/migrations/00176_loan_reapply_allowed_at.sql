-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00176_loan_reapply_allowed_at.sql
-- Purpose   : Kapag ni-reject ng Head Manager o Employee ang loan
--             application, SILA ANG MAGDEDESISYON kung kailan pwedeng
--             mag-apply ulit ang lender.
--
--   Bakit kailangan ng column:
--     Dati, hard-coded ang 1-month cooldown sa `loans-apply` (base sa
--     `loans.updated_at` ng pinakahuling rejected loan). Walang paraan ang
--     staff na paikliin (hal. kulang lang ang dokumento — pwede agad) o
--     pahabain (hal. paulit-ulit na bad record) ang window.
--
--   Semantics:
--     loans.reapply_allowed_at = oras/petsa kung kailan PWEDE nang mag-apply
--     ulit ang lender. Isang beses lang itong naka-set — sa oras ng rejection
--     (mula sa reject modal ng staff) — at hindi na binabago sa app.
--       * timestamp sa future → naka-block pa (COOLDOWN_ACTIVE)
--       * timestamp sa nakaraan/ngayon → pwede nang mag-apply (hal. "Pwede agad")
--       * NULL → lumang behavior: 1 buwan mula sa loans.updated_at
--              (backward-compatible sa mga lumang rejection at lumang app build)
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

ALTER TABLE loans
  ADD COLUMN IF NOT EXISTS reapply_allowed_at TIMESTAMPTZ;

COMMENT ON COLUMN loans.reapply_allowed_at IS
  'Staff-decided (HM/Employee, sa reject modal) na oras kung kailan pwedeng mag-apply ulit ang lender pagkatapos ng rejection. NULL = default 1-month cooldown mula sa updated_at.';

COMMIT;
