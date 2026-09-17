-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00167_walkin_app_loan_linkage.sql
-- Purpose   : Ang walk-in (In-Office) application na na-submit sa Step 3
--             ("account created + upgrade auto-verified") ay naiiwang
--             status 'submitted' na WALANG loan — at kung mag-apply na si
--             lender sa app, hindi na-relink ang walk-in application nito.
--             Resulta sa Loan Records → In-Office tab: "No loan yet" pa rin
--             kahit ACTIVE na ang loan ng lender.
--
-- ROOT CAUSE
--   • `in-office-view?fn=submit-account` (Step 3) → status 'submitted',
--     account auto-verified, WALANG loan, may message na "Lender may now
--     log in and apply for a loan."
--   • Ang auto-convert ng walk-in → loan ay nasa `kyc-view` lang, at
--     tumatakbo lang kapag may KYC verification event. Dahil auto-verified
--     na ang account sa Step 3, WALA nang event na mangyayari — kaya hindi
--     ito na-convert.
--   • Ang `loans-apply` (lender self-apply) ay gumagawa ng loan na WALANG
--     `in_office_application_id` at hindi ginagalaw ang application.
--   → na-stuck ang application sa 'submitted' + "No loan yet" forever.
--
-- FIX (app side — kasama sa parehong commit)
--   • `loans-apply`: kapag nag-self-apply ang lender at may pending walk-in
--     application siya, ililink ang bagong loan (in_office_application_id)
--     at i-mark na 'converted' ang application.
--   • Loan Records → In-Office tab: hindi na nakalista ang mga draft
--     (draft = hindi pa na-submit na walk-in, kasama ang abandonadong
--     wizard na may draft row agad pagbukas ng "New Walk-in").
--
-- MIGRATION (data repair para sa mga naunang stuck na application)
--   1) I-link sa earliest na hindi pa naka-link na loan ng lender (rejected
--      at cancelled ay hindi binibilang) na ginawa SA ORAS O PAGKATAPOS
--      malikha ang walk-in application — isang application lang kada lender
--      (ang pinakamatagal na naka-submit).
--   2) I-mark na 'converted' ang mga application na mayroon nang naka-link
--      na loan (para lumabas na ang loan number sa halip na "No loan yet").
--   3) Index sa loans(in_office_application_id) para mabilis ang reverse
--      lookup na ginagamit ng `in-office-view?fn=get-list`.
--
-- Idempotent: safe na i-rerun (tinitignan ang status at existing na link).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) I-link ang mga stuck ('submitted') na walk-in application sa loan ng
--    lender na ginawa pagkatapos malikha ang application.
-- ─────────────────────────────────────────────────────────────────────
WITH pending AS (
  -- Isang application kada lender: ang pinakamatagal nang naka-submit na
  -- walang naka-link na loan.
  SELECT DISTINCT ON (a.lender_id)
         a.id         AS app_id,
         a.lender_id  AS lender_id,
         COALESCE(a.submitted_at, a.created_at) AS app_since
    FROM public.in_office_applications a
   WHERE a.status = 'submitted'
     AND a.lender_id IS NOT NULL
     AND NOT EXISTS (
           SELECT 1 FROM public.loans l WHERE l.in_office_application_id = a.id
         )
   ORDER BY a.lender_id, COALESCE(a.submitted_at, a.created_at) ASC
),
candidate AS (
  SELECT p.app_id,
         (SELECT lo.id
            FROM public.loans lo
           WHERE lo.lender_id = p.lender_id
             AND lo.in_office_application_id IS NULL
             AND lo.status NOT IN ('rejected', 'cancelled')
             AND lo.created_at >= p.app_since
           ORDER BY lo.created_at ASC
           LIMIT 1) AS loan_id
    FROM pending p
)
UPDATE public.loans t
   SET in_office_application_id = c.app_id,
       updated_at               = now_manila()
  FROM candidate c
 WHERE t.id = c.loan_id
   AND c.loan_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────
-- 2) I-mark na 'converted' ang mga application na may naka-link nang loan
--    (dati: nananatiling 'submitted' → "No loan yet" sa In-Office tab).
-- ─────────────────────────────────────────────────────────────────────
UPDATE public.in_office_applications a
   SET status      = 'converted',
       wizard_step = 5,
       updated_at  = now_manila()
 WHERE a.status = 'submitted'
   AND EXISTS (
         SELECT 1 FROM public.loans l WHERE l.in_office_application_id = a.id
       );

-- ─────────────────────────────────────────────────────────────────────
-- 3) Reverse lookup index (loans → in_office_applications).
-- ─────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_loans_in_office_application_id
  ON public.loans (in_office_application_id);

COMMIT;
