-- supabase/migrations/00183_xendit_test_payment_idempotency.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Duplicate-request protection para sa XENDIT SANDBOX TEST PAYMENTS
-- (`payments-xendit-link?fn=create-test-payment`).
--
-- BAKIT: ang test payment request ay idempotent sa pamamagitan ng
-- `x-idempotency-key` mula sa client — ang row ay nakatala sa `xendit_logs`
-- (event_type='payment', status='test_created') at ang key ay nasa
-- `payload->>'idempotency_key'`. Ang select-then-insert na check sa Edge
-- Function ay may race: dalawang sabay na request na may parehong key ay
-- maaaring PAREHONG makatawag sa Xendit at makagawa ng dalawang payment
-- request. Ang partial unique index na ito ang huling hadlang (23505), at
-- saka na lang ito babalik sa existing na row.
--
-- NAKA-SCOPE: partial index lang ito para sa test rows — WALANG epekto sa
-- legacy `payment` rows (created/paid/unmatched) o sa disbursement logs, kaya
-- hindi naapektuhan ang existing payment at webhook flows.
--
-- Walang column/table na binabago, at walang RLS policy na iginagalaw:
-- ang `xendit_logs` ay service-role only (RLS enabled, walang policy), kaya
-- ang Edge Function lang ang nakaka-access nito.
--
-- Idempotent: safe na i-rerun (`IF NOT EXISTS`).
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS uq_xendit_logs_test_idempotency
  ON public.xendit_logs ((payload ->> 'idempotency_key'))
  WHERE event_type = 'payment'
    AND status = 'test_created'
    AND payload ? 'idempotency_key';

COMMENT ON INDEX public.uq_xendit_logs_test_idempotency IS
  'Isang Xendit sandbox test payment request kada x-idempotency-key (payments-xendit-link?fn=create-test-payment). Hinaharang ang duplicate na payment request kapag sabay ang dalawang request.';

COMMIT;
