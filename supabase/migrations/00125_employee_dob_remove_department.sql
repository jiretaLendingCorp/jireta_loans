-- 00125: staff date_of_birth + remove department
-- 1) employee_profiles never had date_of_birth, so staff DOB always showed
--    blank in My Profile. Add it (nullable DATE like lender_profiles).
-- 2) department is unused product-wise — drop the column.

ALTER TABLE public.employee_profiles
  ADD COLUMN IF NOT EXISTS date_of_birth DATE;

ALTER TABLE public.employee_profiles
  DROP COLUMN IF EXISTS department;
