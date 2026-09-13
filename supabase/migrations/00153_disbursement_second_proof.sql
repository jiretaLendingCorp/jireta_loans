-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00153_disbursement_second_proof.sql
-- Purpose   : Payagan ang rider na mag-upload ng maximum 2 proof photos
--             para sa Cash on Delivery disbursement. Ang unang photo ay
--             nasa `delivery_proof` (existing); ang pangalawang photo ay
--             nasa bagong `delivery_proof_2` column. Ang edge function
--             `disbursements-delivery` ay nagma-map ng `proof_photo_2`
--             type sa column na ito.
-- =====================================================================

ALTER TABLE public.disbursements
  ADD COLUMN IF NOT EXISTS delivery_proof_2 TEXT;

COMMENT ON COLUMN public.disbursements.delivery_proof_2 IS
  'Storage path ng pangalawang COD proof photo (optional, max 2 photos).';
