-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00163_recount_lender_term_defaults.sql
-- Purpose   : Ayusin ang escalation rule na "i-pause ang lender sa IKAWALANG
--             loan term na natapos na may natitirang utang".
--
--   BUG (bakit HINDI nagla-lock ang account):
--     Ang 00152 ay nag-i-increment lang ng lender_profiles.term_default_count
--     sa loob ng `apply_loan_term_penalties()`, at ang function na iyon ay
--     pumapasa lang sa mga loan na WALANG penalty_logs row:
--
--         AND NOT EXISTS (SELECT 1 FROM penalty_logs pl WHERE pl.loan_id = l.id)
--
--     Kaya kung ang isang loan ay may penalty_logs na MULA PA sa lumang
--     30-day auto-penalty (00138, bago ang 00151/00152), ang loan na iyon ay
--     PERMANENTENG nilalaktawan — hindi na nadadagdagan ang counter kahit
--     natapos nang hindi bayad ang term niya. Resulta: nananatili ang
--     term_default_count = 1 kahit pangalawa nang term default, at HINDI
--     kailanman napapa-pause ang account.
--
--   FIX:
--     Muling bilangin (recount) ang term defaults MULA SA AKTWAL NA DATOS
--     kada sweep — "natapos na ba ang term at may natitirang utang ba noong
--     panahong iyon?" — imbes na umasa lang sa isang counter na dinadagdagan
--     ng penalty insert. Idempotent ito, at sakop ang mga loan na may
--     pre-existing penalty row.
--
--   Depinisyon ng "term default":
--     (a) may loan_schedules ang loan (may term),
--     (b) ang HULING due_date ay nakalipas na (< ngayong araw sa Manila), at
--     (c) ang kabuuang verified payments NA BINAYADAN BAGO O SA ARAW ng
--         huling due date ay KULANG pa sa principal * (1 + interest_rate/100).
--     (c) ang mahalaga: kahit nagbayad pa LATER, default pa rin ito dahil
--     hindi nakabayad "base sa loan term na kinuha niya".
--
--   Pag-unpause: manu-mano pa rin (users-manage?fn=unpause-lender).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) loan_was_term_default(loan_id) — historical, stable na depinisyon.
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
    ) v
  ), FALSE);
$$;

COMMENT ON FUNCTION public.loan_was_term_default(UUID) IS
  'True kapag natapos na ang loan term (huling due_date) at kulang pa ang verified na bayad bago/sa araw ng term end. Historical at stable — hindi nagbabago kahit magbayad pa pagkatapos.';

-- ─────────────────────────────────────────────────────────────────────
-- 2) recount_lender_term_defaults(optional lender_id)
--    Muling binibilang ang term_default_count ng bawat lender mula sa
--    aktwal na datos, at awtomatikong pina-pause ang account kapag >= 2.
--    Nagbabalik ng bilang ng mga bagong na-pause na account.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.recount_lender_term_defaults(p_lender_id UUID DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_lender  RECORD;
  v_defaults INTEGER;
  v_paused  INTEGER := 0;
BEGIN
  FOR v_lender IN
    SELECT DISTINCT l.lender_id
    FROM loans l
    WHERE (p_lender_id IS NULL OR l.lender_id = p_lender_id)
      AND l.lender_id IS NOT NULL
  LOOP
    SELECT COUNT(*) INTO v_defaults
    FROM loans l
    WHERE l.lender_id = v_lender.lender_id
      AND public.loan_was_term_default(l.id);

    UPDATE lender_profiles
    SET term_default_count = v_defaults
    WHERE id = v_lender.lender_id
      AND COALESCE(term_default_count, 0) IS DISTINCT FROM v_defaults;

    IF v_defaults >= 2 THEN
      BEGIN
        UPDATE users
        SET account_status = 'paused'
        WHERE id = v_lender.lender_id
          AND account_status = 'active';

        IF FOUND THEN
          v_paused := v_paused + 1;
          BEGIN
            INSERT INTO notifications (user_id, title, body, type, reference_id, is_read, sent_at)
            VALUES (
              v_lender.lender_id,
              'Account Paused — Contact Our Services',
              'Your account has been paused because a second loan term already closed with an unpaid balance. '
                || 'Please contact our office so we can review and reactivate your account.',
              'account_status_change',
              NULL,
              false,
              now_manila()
            );
          EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'pause notification failed for lender %: %', v_lender.lender_id, SQLERRM;
          END;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'account pause failed for lender %: %', v_lender.lender_id, SQLERRM;
      END;
    END IF;
  END LOOP;

  RETURN v_paused;
END;
$$;

COMMENT ON FUNCTION public.recount_lender_term_defaults(UUID) IS
  'Muling binibilang ang lender_profiles.term_default_count mula sa aktwal na datos (mga loan na natapos ang term na may natitirang utang) at pina-pause ang account kapag >= 2. Idempotent.';

-- ─────────────────────────────────────────────────────────────────────
-- 3) auto_mark_overdue_loans() — idagdag ang recount pagkatapos ng
--    term-end penalty pass, para tumakbo ang escalation kahit ang loan ay
--    may pre-existing penalty row.
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

COMMIT;
