-- /supabase/migrations/00026_enable_realtime.sql
-- Enable Supabase Realtime (Postgres CDC) on the domain tables consumed by the
-- Flutter app. The app's list/dashboard providers subscribe to postgres_changes
-- so screens refresh automatically instead of requiring a manual pull-to-refresh.
--
-- Events are filtered by RLS using the connected user's JWT (the app restores
-- the session from SecureStorage before opening channels), so each role only
-- receives changes for rows its existing SELECT policies already expose.

BEGIN;

ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.loans;
ALTER PUBLICATION supabase_realtime ADD TABLE public.loan_schedules;
ALTER PUBLICATION supabase_realtime ADD TABLE public.payments;
ALTER PUBLICATION supabase_realtime ADD TABLE public.collection_assignments;
ALTER PUBLICATION supabase_realtime ADD TABLE public.credit_investigations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.ci_documents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.kyc_documents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.lender_profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.rider_profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
ALTER PUBLICATION supabase_realtime ADD TABLE public.in_office_applications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.disbursements;
ALTER PUBLICATION supabase_realtime ADD TABLE public.blacklist;
ALTER PUBLICATION supabase_realtime ADD TABLE public.reports;
ALTER PUBLICATION supabase_realtime ADD TABLE public.audit_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.penalty_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.system_config;

COMMIT;
