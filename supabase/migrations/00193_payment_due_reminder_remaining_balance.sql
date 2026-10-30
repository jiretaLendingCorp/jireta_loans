-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00193_payment_due_reminder_remaining_balance.sql
-- Purpose   : Kumpletuhin ang 2-days-before-due reminder (00151/00160).
--
--   ANO ANG KULANG:
--     a) Ang notification body ay `loan_schedules.amount_due` lang ang
--        binabanggit — hindi ang NATITIRANG BALANSE ng lender. Kaya kahit
--        naka-remind na, hindi alam ng lender kung magkano pa ang buong
--        babayaran niya para matapos ang loan niya.
--     b) Kapag partially paid na ang installment, buo pa rin ang
--        `amount_due` ang ipinapakita (hal. ₱2,000 pa rin kahit ₱500 na
--        ang bayad). Dapat ang NATITIRA sa installment ang i-remind.
--
--   ANO ANG GINAGAWA NG MIGRATION NA ITO:
--     - Kinukuha ang canonical outstanding balance per loan mula sa
--       public.loan_outstanding_balance() (total_payable + penalties -
--       verified payments), kaya kasama ang 20% term-end penalty na
--       naitala na (00151/00190).
--     - Ang installment amount sa message ay `amount_due - amount_paid`
--       (verified payments lang), kaya tama kahit partial payment.
--     - Idempotent pa rin per schedule (`payment_due` notification na may
--       parehong reference_id) — hindi ito nauulit kapag tumakbo muli.
--     - Ine-enqueue pa rin ang sms-send edge function para sa TextBee SMS
--       batch; ang in-app + FCM push ay galing sa notifications insert
--       (trg_notification_enqueue_push, 00126).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Ang notification type ay dapat naka-seed bago ang insert (FK sa
--    notification_types.code). Naka-seed na ito sa 00151; defensive lang
--    ito para sa fresh database na hindi pa na-apply ang 00151.
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO notification_types (code, label, sort_order) VALUES
  ('payment_due', 'Payment Due', 29)
ON CONFLICT (code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────
-- 2) send_payment_due_reminders()
--    N araw bago ang due date (system_config.payment_reminder_days,
--    default 2): in-app + FCM push notification na may NATITIRANG
--    BALANSE, at SMS batch sa TextBee.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_payment_due_reminders()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_days        INTEGER := 2;
  v_target      RECORD;
  v_count       INTEGER := 0;
  v_outstanding NUMERIC(14,2);
  v_due_amount  NUMERIC(14,2);
  v_url         TEXT;
  v_secret      TEXT;
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
    -- Natitira pa sa installment na ito (verified payments lang ang bawas).
    v_due_amount := GREATEST(
      0,
      ROUND(v_target.amount_due - COALESCE(v_target.amount_paid, 0), 2)
    );
    IF v_due_amount <= 0 THEN
      CONTINUE;
    END IF;

    -- Natitirang balanse ng BUONG loan — kasama ang penalties na naitala
    -- na. Ito ang halagang kailangang mabayad para matapos ang term.
    v_outstanding := public.loan_outstanding_balance(v_target.loan_id);
    IF v_outstanding IS NULL OR v_outstanding < 0 THEN
      v_outstanding := v_due_amount;  -- fallback: huwag mag-remind ng 0
    END IF;

    -- In-app + FCM push (source of truth). Hindi tinatakdaan ang
    -- fcm_sent, kaya ang trg_notification_enqueue_push (00126) ang
    -- mag-e-enqueue ng device push.
    INSERT INTO notifications (user_id, title, body, type, reference_id, is_read, sent_at)
    VALUES (
      v_target.lender_id,
      'Payment Due in ' || v_days::TEXT || ' Days',
      'Reminder: your payment of ₱' || to_char(v_due_amount, 'FM999,999,999.00')
        || ' is due on ' || to_char(v_target.due_date, 'Mon DD, YYYY')
        || '. Your remaining balance is ₱'
        || to_char(v_outstanding, 'FM999,999,999.00')
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
  'Nagpapadala ng payment reminder notification N araw bago ang due date (system_config.payment_reminder_days, default 2) na may natitirang balanse ng loan at net amount ng installment. Idempotent per schedule, at nag-e-enqueue ng TextBee SMS batch.';

-- ─────────────────────────────────────────────────────────────────────
-- 3) Siguraduhing naka-schedule pa rin ang daily sweep. Kung na-apply na
--    ang 00151, iisa lang ang job name kaya hindi ito na-dodoble.
-- ─────────────────────────────────────────────────────────────────────
DO $cron_do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    RAISE NOTICE 'cron schema not present — skipping pg_cron schedule for payment reminders';
    RETURN;
  END IF;

  BEGIN
    PERFORM cron.unschedule('send_payment_due_reminders_daily');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  PERFORM cron.schedule(
    'send_payment_due_reminders_daily',
    '0 0 * * *',
    $cron_job$ SELECT public.send_payment_due_reminders(); $cron_job$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Could not schedule send_payment_due_reminders_daily (non-fatal): %', SQLERRM;
END $cron_do$;

COMMIT;
