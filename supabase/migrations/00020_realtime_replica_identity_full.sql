-- 00020_realtime_replica_identity_full.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Why: Supabase Realtime only delivers UPDATE/DELETE events on RLS-enabled
-- tables when the table has `REPLICA IDENTITY FULL`. Without it, realtime
-- silently drops those events and clients (e.g. the rider app) never see the
-- status changes of collection_assignments (accept → in_progress → completed),
-- payments, disbursements, loans, etc. INSERT events still arrive, which is why
-- new assignments showed up but status changes never did.
--
-- This sets REPLICA IDENTITY FULL on every table that is (a) part of the
-- supabase_realtime publication and (b) protected by RLS, so realtime can
-- evaluate the row for delivery.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.notifications            REPLICA IDENTITY FULL;
ALTER TABLE public.loans                    REPLICA IDENTITY FULL;
ALTER TABLE public.loan_schedules           REPLICA IDENTITY FULL;
ALTER TABLE public.payments                 REPLICA IDENTITY FULL;
ALTER TABLE public.collection_assignments   REPLICA IDENTITY FULL;
ALTER TABLE public.credit_investigations    REPLICA IDENTITY FULL;
ALTER TABLE public.ci_documents             REPLICA IDENTITY FULL;
ALTER TABLE public.account_upgrade_documents REPLICA IDENTITY FULL;
ALTER TABLE public.lender_profiles          REPLICA IDENTITY FULL;
ALTER TABLE public.rider_profiles           REPLICA IDENTITY FULL;
ALTER TABLE public.employee_profiles        REPLICA IDENTITY FULL;
ALTER TABLE public.users                    REPLICA IDENTITY FULL;
ALTER TABLE public.in_office_applications   REPLICA IDENTITY FULL;
ALTER TABLE public.disbursements            REPLICA IDENTITY FULL;
ALTER TABLE public.reports                  REPLICA IDENTITY FULL;
ALTER TABLE public.audit_logs               REPLICA IDENTITY FULL;
ALTER TABLE public.penalty_logs             REPLICA IDENTITY FULL;
ALTER TABLE public.system_config            REPLICA IDENTITY FULL;
ALTER TABLE public.addresses                REPLICA IDENTITY FULL;