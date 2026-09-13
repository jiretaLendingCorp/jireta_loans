-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00154_collection_request_assign_timestamps.sql
-- Purpose   : I-record ang TUNAY na date/time ng dalawang event sa
--             collection_assignments para maipakita nang tama sa
--             Head Manager at Employee screens:
--               requested_at — kung kailan nag-request si lender na
--                 magbayad via rider (dating walang column; created_at
--                 lang ang meron pero hindi ito sapat kapag staff-created
--                 ang assignment).
--               assigned_at  — kung kailan nag-assign ng rider si staff
--                 (dating HINDI nire-record kahit saan; ang updated_at ay
--                 nagbabago rin sa record/proof steps kaya mali itong
--                 gamitin bilang assign time).
--             Ang edge function `collections-manage` ang nagse-set ng mga
--             ito (request/assign handlers); `collections-view` ang
--             nagbabalik sa app.
-- =====================================================================

ALTER TABLE public.collection_assignments
  ADD COLUMN IF NOT EXISTS requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;

-- Backfill: ang mga request na ginawa ni lender (requested_by NOT NULL) ay
-- naganap noong created_at; ang staff-created assignments (requested_by NULL)
-- ay na-assign noong created_at.
UPDATE public.collection_assignments
SET requested_at = created_at
WHERE requested_by IS NOT NULL AND requested_at IS NULL;

UPDATE public.collection_assignments
SET assigned_at = created_at
WHERE rider_id IS NOT NULL AND assigned_at IS NULL;

COMMENT ON COLUMN public.collection_assignments.requested_at IS
  'Kung kailan nag-request si lender ng rider collection.';
COMMENT ON COLUMN public.collection_assignments.assigned_at IS
  'Kung kailan nag-assign ng rider si staff (HM/Employee).';
