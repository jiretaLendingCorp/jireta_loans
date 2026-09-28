-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00178_revert_00177_overdue_term_rule.sql
-- Purpose   : I-UNDO ang 00177_overdue_when_chosen_term_ends.
--
--   BUG na idinulot ng 00177:
--     Nagdagdag ito sa auto_mark_overdue_loans() ng TERM-END rule na
--     `MAX(due_date) <= (now_manila())::date` — ibig sabihin, minamarkahan
--     na agad na OVERDUE ang loan sa MISMOONG ARAW ng huling due date.
--     Kaya ang 1-day daily loan (due = release + 1 day) ay Overdue na sa
--     araw ng due date mismo, imbes na sa sumunod na araw. ("bukas pa
--     dapat mag-overdue")
--
--   FIX (revert):
--     1) Ibalik ang auto_mark_overdue_loans() sa pre-00177 (00163) na
--        bersyon: mid-term rule (30+ araw) + apply_loan_term_penalties()
--        (na `< today` ang huling due date bago mag-overdue/penalty) lang.
--     2) Alisin ang comment na idinagdag ng 00177.
--     3) Data repair: ibalik sa 'active' ang mga loan na na-false-flag na
--        'overdue' ng term-end rule ng 00177 (huling due date = NGAYON,
--        may balanse, walang penalty, at hindi 30-day mid-term case).
--
--   Idempotent: safe na i-rerun. Ang 00177 history row ay hindi iginagalaw
--   (tama lang na manatili ito; itong 00178 ang nagre-revert).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Ibalik ang auto_mark_overdue_loans() sa bersyon ng 00163
--    (WALANG term-end `<=` rule).
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auto_mark_overdue_loans()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- Mid-term delinquency flag lang (walang penalty): may installment na
  -- 30+ araw nang lampas at wala pang kahit isang verified payment.
  UPDATE loans
  SET status = 'overdue'
  WHERE status = 'active'
    AND id IN (
      SELECT ls.loan_id
      FROM loan_schedules ls
      LEFT JOIN payments p ON p.loan_schedule_id = ls.id AND p.status = 'verified'
      WHERE ls.due_date < (now_manila() - INTERVAL '30 days')::date
      GROUP BY ls.loan_id, ls.id
      HAVING COALESCE(SUM(p.amount), 0) = 0
    );

  -- End of term: 20% penalty (base sa current outstanding) + notification.
  PERFORM public.apply_loan_term_penalties();

  -- Escalation: muling bilangin ang term defaults mula sa aktwal na datos at
  -- i-pause ang lender na umabot na sa 2 (robust kahit may lumang penalty row).
  BEGIN
    PERFORM public.recount_lender_term_defaults();
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'recount_lender_term_defaults failed (non-fatal): %', SQLERRM;
  END;

  -- I-expire ang rider assignments na naka-kabit sa overdue loans.
  PERFORM * FROM expire_overdue_assignments();
END;
$$;

-- 00177 ang naglagay ng comment dito; wala ito bago ang 00177.
COMMENT ON FUNCTION public.auto_mark_overdue_loans() IS NULL;

-- ─────────────────────────────────────────────────────────────────────
-- 2) Data repair — ibalik sa 'active' ang mga loan na mali ang pagka-flag
--    ng 00177 term-end rule. Saktong-sakto lang sa mga 00177 artifact:
--      • kasalukuyang 'overdue'
--      • may schedule at ang HULING due date ay NGAYON (Manila)
--        (pre-00177: active pa ito; overdues lang sa susunod na araw)
--      • may natitirang balanse (gaya ng kondisyon ng 00177)
--      • walang penalty (ibig sabihin, hindi pa tunay na natapos ang term)
--      • HINDI 30-day mid-term overdue (may unpaid schedule na 30+ araw)
--    Sinusundan ng trg_loan_status_flow (overdue → active ay allowed).
-- ─────────────────────────────────────────────────────────────────────
UPDATE public.loans l
SET status = 'active',
    updated_at = now_manila()
WHERE l.status = 'overdue'
  AND EXISTS (SELECT 1 FROM public.loan_schedules ls WHERE ls.loan_id = l.id)
  AND (SELECT MAX(ls.due_date) FROM public.loan_schedules ls WHERE ls.loan_id = l.id)
      = (now_manila())::date
  AND COALESCE(public.loan_outstanding_balance(l.id), 0) > 0
  AND NOT EXISTS (SELECT 1 FROM public.penalty_logs pl WHERE pl.loan_id = l.id)
  AND NOT EXISTS (
    SELECT 1
    FROM public.loan_schedules ls
    LEFT JOIN public.payments p
      ON p.loan_schedule_id = ls.id AND p.status = 'verified'
    WHERE ls.loan_id = l.id
      AND ls.due_date < (now_manila() - INTERVAL '30 days')::date
    GROUP BY ls.id
    HAVING COALESCE(SUM(p.amount), 0) = 0
  );

COMMIT;
