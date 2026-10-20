-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00185_term_default_exclude_unreleased_loans.sql
-- Purpose   : I-pause lang ang lender sa IKAWALANG loan na natapos ang
--             term na may natitirang utang — HINDI kasama ang mga
--             application na hindi naman na-release.
--
--   BUG (maling pause):
--     Ang `loans-apply` (at `kyc-view` / `in-office-view`) ay gumagawa na
--     ng `loan_schedules` rows sa ORAS NG APPLICATION, bago pa ma-approve
--     o ma-release. Ang mga due date na iyon ay nire-rebase lang kapag
--     na-release na ang loan (`startLoanPaymentSchedule`).
--
--     Ang `loan_was_term_default()` (00163) ay WALANG status filter — kaya
--     ang isang rejected / pending / cancelled na application na tumagal
--     lampas sa due dates nito ay binibilang ding "term default" kahit
--     hindi kailanman na-release ang pera. Dalawang ganitong application
--     → term_default_count >= 2 → na-pa-pause ang lender nang wala sa
--     business rule.
--
--   FIX:
--     Bilangin lang ang mga loan na TALAGANG tumakbo ang term:
--     `active`, `overdue`, `completed`. Ang tatlong ito lang ang na-release
--     (nagiging `active` ang loan sa disbursement) o tapos nang bayaran.
--     Excluded na ang `pending`, `under_review`, `approved`, `rejected`,
--     `cancelled` — kahit may schedule rows pa ang mga ito.
--
--   Ang mismong escalation (2nd term default → `paused`) ay HINDI binabago;
--   nasa 00152 pa rin. Ang migration na ito ay nagtatakda lang kung aling
--   loans ang dapat bilangin.
--
--   Pag-unpause: manu-mano pa rin (users-manage?fn=unpause-lender).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) loan_was_term_default(loan_id) — idagdag ang status guard.
--    Pareho pa rin ang depinisyon: (a) may term, (b) tapos na ang huling
--    due date, (c) kulang ang verified payments na binayad bago o sa
--    araw ng huling due date — kahit magbayad pa LATER, default pa rin
--    dahil hindi nakabayad "base sa loan term na kinuha niya".
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.loan_was_term_default(p_loan_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((
    SELECT
      v.term_end IS NOT NULL
      AND v.term_end < (now_manila())::date
      AND COALESCE(v.paid_by_term_end, 0) < v.expected
    FROM (
      SELECT
        (SELECT MAX(ls.due_date) FROM loan_schedules ls WHERE ls.loan_id = l.id) AS term_end,
        ROUND(l.principal_amount * (1 + COALESCE(l.interest_rate, 20) / 100), 2) AS expected,
        (SELECT COALESCE(SUM(p.amount), 0)
           FROM payments p
           JOIN loan_schedules ls2 ON ls2.id = p.loan_schedule_id
          WHERE ls2.loan_id = l.id
            AND p.status = 'verified'
            AND p.created_at::date <= (
              SELECT MAX(ls3.due_date) FROM loan_schedules ls3 WHERE ls3.loan_id = l.id
            )
        ) AS paid_by_term_end
      FROM loans l
      WHERE l.id = p_loan_id
        -- 00185: released/completed loans lang ang may totoong term.
        -- Rejected/pending/cancelled applications ay may schedule rows pa
        -- mula sa application time — hindi dapat mabilang.
        AND l.status IN ('active', 'overdue', 'completed')
    ) v
  ), FALSE);
$$;

COMMENT ON FUNCTION public.loan_was_term_default(UUID) IS
  'True kapag natapos na ang loan term (huling due_date) at kulang pa ang verified na bayad bago/sa araw ng term end. Historical at stable — hindi nagbabago kahit magbayad pa pagkatapos. 00185: active/overdue/completed lang ang binibilang; hindi kasama ang rejected/pending/cancelled applications na may schedule rows mula sa application time.';

-- ─────────────────────────────────────────────────────────────────────
-- 2) Ayusin agad ang mga counter na na-inflate ng bug.
--    Idempotent ang recount — mula sa aktwal na datos ito nagre-recount.
--    HINDI nito awtomatikong ina-unpause ang mga account na na-pause na;
--    manu-manong review pa rin iyon (00152 design).
-- ─────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  PERFORM public.recount_lender_term_defaults();
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'recount_lender_term_defaults failed (non-fatal): %', SQLERRM;
END;
$$;

COMMIT;
