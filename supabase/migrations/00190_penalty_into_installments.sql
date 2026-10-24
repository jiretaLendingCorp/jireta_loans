-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00190_penalty_into_installments.sql
-- Purpose   : ISAMA SA BABAYARAN NG LENDER ANG 20% PENALTY.
--
--   Ang penalty ay dating nasa `penalty_logs` lang at sa DERIVED na
--   `outstanding_balance` (total_payable + penalties - verified payments).
--   Ang `loan_schedules` ay total_payable pa rin ang kabuuan — kaya kapag
--   binayaran ng lender ang lahat ng installment (lalo na via GCash, kung
--   saan EKSAKTONG `loan_schedules.amount_due` ang siningil), may natitira
--   pang 20% na hindi nababayaran at hindi nag-cocompleted ang loan.
--
--   Ngayon: ang penalty ay IDINADAGDAG sa huling unpaid installment, kaya
--   ang kabuuan ng natitirang installment = total_payable + penalties.
--   Mababayaran na ito sa normal na daloy (office cash, rider collection,
--   GCash) at kapag ubos na ang lahat ng installment, 0 na rin ang
--   outstanding balance (kasama ang penalty).
--
--   Idempotent: ang idinadagdag ay ang GAP lamang
--   (total_payable + penalties - kabuuan ng amount_due), kaya hindi ito
--   na-dodoble kahit tawagin pagkatapos ng bawat bayad o sweep.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) sync_loan_schedule_penalties(loan_id)
--    Ibalik ang halagang idinagdag (0 kapag wala nang dapat idagdag).
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_loan_schedule_penalties(p_loan_id UUID)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_total_payable NUMERIC(14,2);
  v_penalties     NUMERIC(14,2);
  v_scheduled     NUMERIC(14,2);
  v_gap           NUMERIC(14,2);
  v_schedule_id   UUID;
BEGIN
  -- Canonical total payable ng loan (kaparehas ng computeTotalPayable sa
  -- `_shared/loan_financials.ts` at ng loan_outstanding_balance()).
  SELECT ROUND(l.principal_amount * (1 + COALESCE(l.interest_rate, 20) / 100), 2)
    INTO v_total_payable
  FROM loans l
  WHERE l.id = p_loan_id;
  IF v_total_payable IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(SUM(pl.penalty_amount), 0)
    INTO v_penalties
  FROM penalty_logs pl
  WHERE pl.loan_id = p_loan_id;
  IF v_penalties <= 0 THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(SUM(ls.amount_due), 0)
    INTO v_scheduled
  FROM loan_schedules ls
  WHERE ls.loan_id = p_loan_id;

  -- Ang bahagi ng penalty na HINDI pa kasama sa mga installment.
  v_gap := ROUND(v_total_payable + v_penalties - v_scheduled, 2);
  -- Wala nang dapat idagdag (o sobra na ang naka-schedule — huwag bawasan).
  IF v_gap <= 0.004 THEN
    RETURN 0;
  END IF;

  -- Huling installment na may natitira pang babayaran. Doon ipinatong ang
  -- penalty, kaya kasama siya sa "Amount" at sa sisingilin ng lahat ng
  -- payment channel (GCash invoice = amount_due).
  --
  -- Fallback: kapag BAYAD NA ang lahat ng installment pero may penalty pa
  -- (lumang data — nabayaran ang total_payable bago/noon na-apply ang 20%),
  -- ang HULING installment pa rin ang gagalawin. Tataas ang amount_due nito
  -- at magiging `partial` — iyon lang ang natitirang penalty, kaya may
  -- mababayaran pa ang lender at hindi stuck ang balance.
  SELECT ls.id
    INTO v_schedule_id
  FROM loan_schedules ls
  WHERE ls.loan_id = p_loan_id
  ORDER BY
    CASE
      WHEN ls.amount_due - COALESCE((
            SELECT SUM(p.amount)
            FROM payments p
            WHERE p.loan_schedule_id = ls.id
              AND p.status = 'verified'
          ), 0) > 0.004 THEN 0
      ELSE 1
    END,
    ls.installment_number DESC
  LIMIT 1;

  -- Wala pang schedule — walang mapagpapatungan. Nananatili pa rin ito sa
  -- outstanding balance at maisasama kapag may schedule na.
  IF v_schedule_id IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE loan_schedules
  SET amount_due = ROUND(amount_due + v_gap, 2),
      updated_at = now_manila()
  WHERE id = v_schedule_id;

  RETURN v_gap;
END;
$$;

COMMENT ON FUNCTION public.sync_loan_schedule_penalties(UUID) IS
  'Idinadagdag sa huling unpaid installment ang 20% penalty (gap ng total_payable + penalties laban sa kabuuan ng amount_due) para kasama ito sa babayaran ng lender. Kapag bayad na ang lahat ng installment, ang huling installment ang ginagawang partial. Idempotent.';

-- ─────────────────────────────────────────────────────────────────────
-- 2) apply_loan_term_penalties() — tawagin ang sync pagkatapos maitala
--    ang penalty (00152 ang huling definition; buong function na naman).
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
  v_defaults    INTEGER;
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

    -- (a2) ISAMA SA BABAYARAN: idagdag ang penalty sa huling unpaid
    --      installment para ang schedule ay umabot sa outstanding balance.
    --      Naka-wrap para hindi masayang ang naitalang penalty kapag may
    --      problema sa schedule (muli naman itong mag-sysync sa susunod).
    BEGIN
      PERFORM public.sync_loan_schedule_penalties(v_loan.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'penalty schedule sync failed for loan %: %', v_loan.id, SQLERRM;
    END;

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

    -- (d) ESCALATION: bilangin ang term defaults ng lender. Kapag ito na
    --     ang PANGALAWA (o higit pa), i-pause ang account. Ang pag-unpause
    --     ay manu-mano (users-manage?fn=unpause-lender) — hindi awtomatiko
    --     kahit mabayaran, para may kontrol ang staff.
    v_defaults := NULL;
    BEGIN
      UPDATE lender_profiles
      SET term_default_count = COALESCE(term_default_count, 0) + 1
      WHERE id = v_loan.lender_id
      RETURNING term_default_count INTO v_defaults;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'term default counter failed for lender %: %', v_loan.lender_id, SQLERRM;
    END;

    IF v_defaults IS NOT NULL AND v_defaults >= 2 THEN
      BEGIN
        UPDATE users
        SET account_status = 'paused'
        WHERE id = v_loan.lender_id
          AND account_status = 'active';

        IF FOUND THEN
          INSERT INTO notifications (user_id, title, body, type, reference_id, is_read, sent_at)
          VALUES (
            v_loan.lender_id,
            'Account Paused — Contact Our Services',
            'Your account has been paused because your loan ' || v_loan.loan_number
              || ' also reached the end of its term with an unpaid balance. '
              || 'This is the second time a loan term closed unpaid. '
              || 'Your outstanding balance is ₱'
              || to_char(v_outstanding + v_penalty, 'FM999,999,999.00')
              || '. Please contact our office so we can review and reactivate your account.',
            'account_status_change',
            v_loan.id,
            false,
            now_manila()
          );
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'account pause failed for lender %: %', v_loan.lender_id, SQLERRM;
      END;
    END IF;

    v_applied := v_applied + 1;
  END LOOP;

  RETURN v_applied;
END;
$$;

COMMENT ON FUNCTION public.apply_loan_term_penalties() IS
  'Isang beses na 20% penalty (base sa kasalukuyang outstanding balance) kapag natapos na ang loan term na may natitirang utang. Idinadagdag din ang penalty sa huling unpaid installment para kasama sa babayaran ng lender. Nagpapadala ng notification sa lender. Kapag pangalawa (o higit pa) nang term default ng lender, awtomatikong naka-pause ang account (users.account_status = paused). Idempotent per loan.';

-- ─────────────────────────────────────────────────────────────────────
-- 3) BACKFILL — isama ang mga penalty na naitala BAGO ang migration na
--    ito, para hindi maiwan ang lumang overdue loans na may 20% na wala
--    sa payment schedule. Idempotent (gap = 0 pagkatapos ng unang tawag).
-- ─────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT pl.loan_id
    FROM penalty_logs pl
    JOIN loan_schedules ls ON ls.loan_id = pl.loan_id
  LOOP
    PERFORM public.sync_loan_schedule_penalties(r.loan_id);
  END LOOP;
END $$;

COMMIT;
