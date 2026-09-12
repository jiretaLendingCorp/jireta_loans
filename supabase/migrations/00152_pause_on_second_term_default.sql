-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00152_pause_on_second_term_default.sql
-- Purpose   : Escalation rule — kapag IKAWALANG beses nang hindi nakabayad
--             ang lender sa katapusan ng loan term niya, i-pause ang account
--             niya. Sa app, makikita niya ang "Contact Our Services" modal
--             at hindi na makakagamit ng app hanggang ma-unpause siya ng
--             Head Manager o Employee.
--
--   Bakit term-based at hindi per-installment:
--     Ang 20% penalty (00151) ay naka-base sa KASALUKUYANG outstanding
--     balance ng loan at isang beses lang kada loan. Kaya ang bawat loan
--     na natapos ang term na may utang ay may sariling penalty — at kapag
--     pangalawa na ito para sa lender, dito na pumapasok ang pause.
--
--   Marker: lender_profiles.term_default_count
--     Increment kada term-end penalty. Kapag umabot sa 2 → pause.
--     (Imbes na magbilang sa penalty_logs.reason text, explicit counter
--     para deterministic at madaling i-audit.)
--
--   Pag-unpause: manu-mano — users-manage?fn=unpause-lender (HM o Employee).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Bagong account status: 'paused'
--    Ibang estado ito sa 'inactive' (ginagamit ng staff para sa ibang
--    dahilan) at sa 'archived' (permanenteng naka-block sa login), kaya
--    hiwalay na code ang kailangan para tumpak na maipakita ng app ang
--    "Contact Our Services" modal para sa pause-dahil-sa-loan-default.
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO user_account_statuses (code, label, sort_order) VALUES
  ('paused', 'Paused', 3)
ON CONFLICT (code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────
-- 2) term_default_count sa lender_profiles
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE lender_profiles
  ADD COLUMN IF NOT EXISTS term_default_count INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN lender_profiles.term_default_count IS
  'Bilang ng beses na natapos ang loan term ng lender na may natitirang utang (term-end 20% penalty). Kapag umabot sa 2, awtomatikong na-pa-pause ang users.account_status.';

-- ─────────────────────────────────────────────────────────────────────
-- 3) apply_loan_term_penalties() — idagdag ang pause escalation.
--    (Buong function na ni-replace para hindi na kailangan ng ALTER.)
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
  'Isang beses na 20% penalty (base sa kasalukuyang outstanding balance) kapag natapos na ang loan term na may natitirang utang. Nagpapadala ng notification sa lender. Kapag pangalawa (o higit pa) nang term default ng lender, awtomatikong naka-pause ang account (users.account_status = paused). Idempotent per loan.';

COMMIT;
