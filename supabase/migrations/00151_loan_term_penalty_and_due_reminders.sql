-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00151_loan_term_penalty_and_due_reminders.sql
-- Purpose   : Fix the two loan-money rules + their notifications.
--
--   RULE 1 — 20% penalty at the END OF THE LOAN TERM
--     Dati (00138): ang 20% penalty ay naka-base sa TOTAL PAYABLE
--       (principal * 1.20) at nagti-trigger 30 ARAW pagkatapos ng due date.
--       Dalawa ang mali:
--         a) mali ang base — sinisingil pa rin ang interest kahit bayad na
--            ang principal portion; at
--         b) nawawala ang notification — ang auto penalty ay nag-iinsert
--            lang sa penalty_logs, WALANG notification. Kaya hindi alam ng
--            lender na tumaas na ang utang niya. (Ang manual apply-penalty
--            lang sa loans-manage ang may notify.)
--     Ngayon: kapag lumipas na ang HULING due date ng loan (end of term) at
--       may natitirang balanse, ang penalty ay 20% ng KASALUKUYANG
--       OUTSTANDING BALANCE (hindi ng total payable), isang beses lang,
--       at may notification agad sa lender.
--
--   RULE 2 — REMINDER 2 ARAW BAGO ANG DUE DATE
--     Dati: umiiral ang sms-send?fn=send-reminder pero WALANG nagti-trigger
--       nito (walang cron, walang button) — kaya walang reminder na
--       nangyayari. Bukod pa, ang notification type na 'payment_due' ay
--       hindi naka-seed sa notification_types, kaya ang in-app/push insert
--       ay nabigo sa FK constraint (silently swallowed).
--     Ngayon: send_payment_due_reminders() ang nag-o-own ng in-app + push
--       notification (para tumakbo kahit hindi naka-configure ang SMS),
--       at ini-enqueue nito ang SMS batch sa sms-send edge function.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Seed the notification types na ginagamit ng mga bagong notification.
--    'payment_due' ay ginagamit ng reminder (sms-send/index.ts) pero hindi
--    naka-seed sa 00001 → FK violation → walang notification na naipapasok.
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO notification_types (code, label, sort_order) VALUES
  ('payment_due', 'Payment Due', 29)
ON CONFLICT (code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────
-- 2) Canonical outstanding balance for a loan.
--    total_payable + penalties - verified payments (>= 0)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.loan_outstanding_balance(p_loan_id UUID)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
  SELECT GREATEST(0, ROUND(
      l.principal_amount * (1 + COALESCE(l.interest_rate, 20) / 100)
    + COALESCE((SELECT SUM(pl.penalty_amount) FROM penalty_logs pl WHERE pl.loan_id = l.id), 0)
    - COALESCE((SELECT SUM(p.amount)
                FROM payments p
                JOIN loan_schedules ls ON ls.id = p.loan_schedule_id
                WHERE ls.loan_id = l.id AND p.status = 'verified'), 0)
  , 2))
  FROM loans l
  WHERE l.id = p_loan_id;
$$;

COMMENT ON FUNCTION public.loan_outstanding_balance(UUID) IS
  'Outstanding balance ng isang loan: total_payable + penalties - verified payments. Base ito ng 20% term-end penalty.';

-- ─────────────────────────────────────────────────────────────────────
-- 3) apply_loan_term_penalties()
--    Kapag lumipas na ang huling due date ng loan at may natitirang
--    balanse → +20% ng KASALUKUYANG OUTSTANDING (isang beses lang) +
--    notification sa lender. Idempotent: nilalaktawan ang loan na may
--    penalty_logs na (kaya hindi ito naco-compound at hindi na-dodoble).
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.apply_loan_term_penalties()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_loan        RECORD;
  v_rate        NUMERIC(5,2)  := 20;
  v_rate_label  TEXT;
  v_outstanding NUMERIC(14,2);
  v_penalty     NUMERIC(14,2);
  v_applied     INTEGER := 0;
BEGIN
  -- Naka-wrap sa exception block para hindi masabotahe ang buong sweep ng
  -- isang non-numeric config value (cast error sana ang mangyayari).
  BEGIN
    SELECT btrim(config_value)::NUMERIC INTO v_rate
    FROM system_config
    WHERE config_key = 'penalty_rate';
  EXCEPTION WHEN OTHERS THEN
    v_rate := 20;
  END;
  IF v_rate IS NULL OR v_rate <= 0 THEN
    v_rate := 20;
  END IF;

  -- '20' imbes na '20.00' sa mga mensahe.
  v_rate_label := CASE
    WHEN v_rate = trunc(v_rate) THEN trunc(v_rate)::INTEGER::TEXT
    ELSE to_char(v_rate, 'FM990.99')
  END;

  FOR v_loan IN
    SELECT
      l.id,
      l.lender_id,
      l.loan_number,
      (SELECT MAX(ls.due_date) FROM loan_schedules ls WHERE ls.loan_id = l.id) AS term_end
    FROM loans l
    WHERE l.status IN ('active', 'overdue')
      AND NOT EXISTS (SELECT 1 FROM penalty_logs pl WHERE pl.loan_id = l.id)
      AND EXISTS (SELECT 1 FROM loan_schedules ls WHERE ls.loan_id = l.id)
  LOOP
    -- End of term pa lang ba? Kung hindi pa tapos ang term, walang penalty.
    IF v_loan.term_end IS NULL OR v_loan.term_end >= (now_manila())::date THEN
      CONTINUE;
    END IF;

    v_outstanding := public.loan_outstanding_balance(v_loan.id);
    IF v_outstanding IS NULL OR v_outstanding <= 0 THEN
      CONTINUE;  -- bayad na — huwag nang singilin
    END IF;

    -- 20% ng KASALUKUYANG outstanding balance (hindi ng total payable).
    v_penalty := ROUND(v_outstanding * v_rate / 100, 2);
    IF v_penalty <= 0 THEN
      CONTINUE;
    END IF;

    -- (a) I-record ang penalty. penalty_basis = ang outstanding na
    --     ginamit — kaya auditable kung magkano ang base noon.
    INSERT INTO penalty_logs (
      loan_id, applied_by, penalty_basis, penalty_rate, penalty_amount, reason
    ) VALUES (
      v_loan.id,
      NULL,                       -- system-applied (00138 made applied_by nullable)
      v_outstanding,
      v_rate,
      v_penalty,
      'Automatic ' || v_rate_label || '% penalty — loan term ended with an unpaid balance'
    );

    -- (b) Mark overdue (nag-expire na ang term, may utang pa).
    UPDATE loans
    SET status = 'overdue', updated_at = now_manila()
    WHERE id = v_loan.id AND status = 'active';

    -- (c) I-notify ang lender. Ang notifications insert na ito ay
    --     awtomatikong ipi-push ng trg_notification_enqueue_push (00126).
    --     Naka-wrap sa exception block para kahit mabigo ang notification,
    --     hindi mawawala ang penalty na kaka-record lang.
    BEGIN
      INSERT INTO notifications (user_id, title, body, type, reference_id, is_read, sent_at)
      VALUES (
        v_loan.lender_id,
        'Active Loan Increased by ' || v_rate_label || '%',
        'Your loan ' || v_loan.loan_number || ' reached the end of its term with an unpaid balance. '
          || 'A ' || v_rate_label || '% penalty of ₱' || to_char(v_penalty, 'FM999,999,999.00')
          || ' was added on top of your current active loan balance of ₱'
          || to_char(v_outstanding, 'FM999,999,999.00')
          || '. Your new outstanding balance is ₱'
          || to_char(v_outstanding + v_penalty, 'FM999,999,999.00')
          || '. Please settle it to avoid further charges.',
        'penalty_applied',
        v_loan.id,
        false,
        now_manila()
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'term-end penalty notification failed for loan %: %', v_loan.id, SQLERRM;
    END;

    v_applied := v_applied + 1;
  END LOOP;

  RETURN v_applied;
END;
$$;

COMMENT ON FUNCTION public.apply_loan_term_penalties() IS
  'Isang beses na 20% penalty (base sa kasalukuyang outstanding balance) kapag natapos na ang loan term na may natitirang utang. Nagpapadala ng notification sa lender. Idempotent — nilalaktawan ang loan na may existing penalty_logs.';

-- ─────────────────────────────────────────────────────────────────────
-- 4) send_payment_due_reminders()
--    Nag-iinsert ng 'payment_due' notification sa lender N araw bago ang
--    due date ng isang installment (default 2 araw, mula sa
--    system_config.payment_reminder_days). Idempotent — hindi na-uulit ang
--    notification para sa parehong schedule. Sa dulo, ini-enqueue rin ang
--    SMS batch sa sms-send edge function (kung naka-configure).
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_payment_due_reminders()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_days   INTEGER := 2;
  v_target RECORD;
  v_count  INTEGER := 0;
  v_url    TEXT;
  v_secret TEXT;
BEGIN
  BEGIN
    SELECT btrim(config_value)::INTEGER INTO v_days
    FROM system_config
    WHERE config_key = 'payment_reminder_days';
  EXCEPTION WHEN OTHERS THEN
    v_days := 2;
  END;
  IF v_days IS NULL OR v_days < 0 THEN
    v_days := 2;
  END IF;

  FOR v_target IN
    SELECT
      s.id            AS schedule_id,
      s.due_date,
      s.amount_due,
      l.id            AS loan_id,
      l.loan_number,
      l.lender_id,
      COALESCE(p.amount_paid, 0) AS amount_paid
    FROM loan_schedules s
    JOIN loans l ON l.id = s.loan_id
    LEFT JOIN (
      SELECT loan_schedule_id, SUM(amount) AS amount_paid
      FROM payments
      WHERE status = 'verified'
      GROUP BY loan_schedule_id
    ) p ON p.loan_schedule_id = s.id
    WHERE s.due_date = (now_manila())::date + v_days
      AND l.status IN ('active', 'overdue')
      AND COALESCE(p.amount_paid, 0) < s.amount_due
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.type = 'payment_due'
          AND n.reference_id = s.id
          AND n.user_id = l.lender_id
      )
  LOOP
    INSERT INTO notifications (user_id, title, body, type, reference_id, is_read, sent_at)
    VALUES (
      v_target.lender_id,
      'Payment Due in ' || v_days::TEXT || ' Days',
      'Reminder: your payment of ₱' || to_char(v_target.amount_due, 'FM999,999,999.00')
        || ' for loan ' || v_target.loan_number || ' is due on '
        || to_char(v_target.due_date, 'Mon DD, YYYY')
        || '. Please pay on time — if the loan term ends with an unpaid balance, '
        || 'a 20% penalty is charged on the outstanding balance at that time.',
      'payment_due',
      v_target.schedule_id,
      false,
      now_manila()
    );
    v_count := v_count + 1;
  END LOOP;

  -- SMS channel (best effort). Ang in-app/push notification sa itaas ang
  -- laging tumatakbo; ito ay dagdag lang. No-op kapag hindi pa naka-set ang
  -- sms_reminder_function_url.
  BEGIN
    SELECT config_value INTO v_url    FROM system_config WHERE config_key = 'sms_reminder_function_url';
    SELECT config_value INTO v_secret FROM system_config WHERE config_key = 'push_function_secret';

    IF v_url IS NOT NULL AND v_url <> '' AND v_url NOT LIKE '%REPLACE_ME%' THEN
      PERFORM net.http_post(
        url := v_url || '?fn=send-reminder',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'x-push-secret', COALESCE(v_secret, '')
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 10000
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'payment reminder SMS enqueue failed (non-fatal): %', SQLERRM;
  END;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.send_payment_due_reminders() IS
  'Nagpapadala ng payment reminder notification N araw bago ang due date (system_config.payment_reminder_days, default 2). Idempotent per schedule, at nag-e-enqueue ng SMS batch.';

-- ─────────────────────────────────────────────────────────────────────
-- 5) auto_mark_overdue_loans() — pinanatili ang mid-term overdue flag,
--    pero ang penalty ay sa end of term na (Rule 1) at may notification.
--    Ang '30 days past due' na penalty ay tinanggal na (nasa
--    apply_loan_term_penalties na ang tanging penalty trigger).
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

  -- I-expire ang rider assignments na naka-kabit sa overdue loans.
  PERFORM * FROM expire_overdue_assignments();
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 6) system_config: SMS reminder function URL + update ng descriptions
--    na tumutukoy sa lumang 30-day rule.
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO system_config (config_key, config_value, description)
VALUES (
  'sms_reminder_function_url',
  'https://lcelzrvpqwlbeccrwpkp.supabase.co/functions/v1/sms-send',
  'URL ng sms-send edge function na ini-enqueue ng send_payment_due_reminders() para sa SMS reminder N araw bago ang due date. Palitan ng project ref kung iba.'
)
ON CONFLICT (config_key) DO NOTHING;

UPDATE system_config
SET description = 'Penalty rate percentage applied once when the loan term ends with an unpaid balance (base: current outstanding balance)',
    updated_at = now()
WHERE config_key = 'penalty_rate';

UPDATE system_config
SET description = 'Days before a due date to send the payment reminder (in-app, push, and SMS)'
WHERE config_key = 'payment_reminder_days';

-- ─────────────────────────────────────────────────────────────────────
-- 7) pg_cron schedules (best effort, guarded like 00114/00138).
--    - Term-end penalty/push check: every hour (para hindi mahuli ng isang
--      araw ang penalty sa katapusan ng term).
--    - Due-date reminder: araw-araw. Ang oras ng pg_cron ay depende sa
--      timezone ng database (UTC sa Supabase), kaya 00:00 UTC = 08:00 Manila.
--      Hindi mahalaga ang exact na oras: ang send_payment_due_reminders()
--      mismo ay gumagamit ng now_manila() para sa date math, at idempotent
--      ito per schedule.
-- ─────────────────────────────────────────────────────────────────────
DO $cron_do$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron extension not available — skipping cron schedules (functions can be run manually)';
    RETURN;
  END;

  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    RAISE NOTICE 'cron schema not present — skipping pg_cron schedules';
    RETURN;
  END IF;

  -- Term-end penalty + overdue sweep. Replaces the old daily job so the
  -- penalty lands within the hour the term actually ends.
  BEGIN
    PERFORM cron.unschedule('auto_mark_overdue_loans_daily');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    PERFORM cron.unschedule('auto_mark_overdue_loans_hourly');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM cron.schedule(
    'auto_mark_overdue_loans_hourly',
    '10 * * * *',
    $cron_job$ SELECT public.auto_mark_overdue_loans(); $cron_job$
  );

  -- 2-days-before-due reminder (in-app + push + SMS).
  BEGIN
    PERFORM cron.unschedule('send_payment_due_reminders_daily');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM cron.schedule(
    'send_payment_due_reminders_daily',
    '0 0 * * *',
    $cron_job$ SELECT public.send_payment_due_reminders(); $cron_job$
  );

  RAISE NOTICE 'pg_cron jobs scheduled: auto_mark_overdue_loans_hourly (hourly), send_payment_due_reminders_daily (00:00 UTC)';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Could not schedule pg_cron jobs (non-fatal): %', SQLERRM;
END $cron_do$;

COMMIT;
