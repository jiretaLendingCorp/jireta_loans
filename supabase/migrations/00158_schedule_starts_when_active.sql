-- supabase/migrations/00158_schedule_starts_when_active.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- BUSINESS RULE: ang payment schedule (loan_schedules) ay para lang sa
-- ACTIVE / OVERDUE (at naging `completed`) na loan — nagsisimula ang mga
-- installment sa petsa ng RELEASE, hindi sa petsa ng application.
--
-- Dati, ginagawa na ang schedule sa oras ng application (loans-apply /
-- kyc-view / in-office-view), kaya:
--   • may "Payment Schedule" na nakikita sa Loan Application Details kahit
--     hindi pa aktivado ang loan, at
--   • pagka-release (ilang araw pagkatapos), overdue na agad ang unang mga
--     installment dahil sa petsa ng application naka-base ang due dates.
--
-- Ngayon, sa pag-activate/disburse na lang ginagawa ang schedule
-- (`startLoanPaymentSchedule` sa bawat release path), kaya ang migration na
-- ito ay naglilinis ng lumang pre-activation rows.
--
-- LIGTAS: hindi ginagalaw ang anumang schedule na may VERIFIED payment
-- (partially/fully paid na loan), at idempotent (puwedeng i-run muli).
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

DELETE FROM public.loan_schedules s
USING public.loans l
WHERE s.loan_id = l.id
  AND COALESCE(l.status, '') NOT IN ('active', 'overdue', 'completed')
  AND NOT EXISTS (
    SELECT 1
    FROM public.payments p
    WHERE p.loan_schedule_id = s.id
      AND p.status = 'verified'
  );

COMMIT;
