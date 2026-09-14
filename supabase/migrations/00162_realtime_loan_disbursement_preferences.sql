-- 00162_realtime_loan_disbursement_preferences.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Bug: kapag pumili ang lender ng disbursement method (Cash on Delivery /
-- Pick Up at Office), isang upsert lang sa `loan_disbursement_preferences`
-- ang nangyayari — hindi nagbabago ang `loans` row. Dahil HINDI kasama ang
-- `loan_disbursement_preferences` sa `supabase_realtime` publication, walang
-- Realtime event na natatanggap ang HM/Employee Loan Records screens kaya
-- HINDI lumalabas ang ORANGE indicator sa 3-dot action (at ang
-- "Assign Cash on Delivery Rider" na menu) hanggang manual refresh.
--
-- Ang client providers (hm_loan_provider / emp_loan_provider) ay
-- naka-subscribe na sa table na ito — kailangan lang i-publish ito.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'loan_disbursement_preferences'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.loan_disbursement_preferences;
    RAISE NOTICE 'Added public.loan_disbursement_preferences to supabase_realtime';
  ELSE
    RAISE NOTICE 'public.loan_disbursement_preferences already published';
  END IF;
END $$;
