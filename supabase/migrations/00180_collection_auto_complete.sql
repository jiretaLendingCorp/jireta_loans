-- supabase/migrations/00180_collection_auto_complete.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Business rule (BINAGO): kapag na-collect na ng rider ang pera at nai-submit
-- ang amount/proof (`?fn=record` / `?fn=upload-proof`), `completed` NA AGAD ang
-- `collection_assignments` — WALANG approval na kailangan ng Head Manager o
-- Employee. Ang `verified` payment ay binibilang agad sa loan balance (ang
-- balance gate na ginawa sa 00159 ay para lang sa `pending_approval`/`rejected`
-- na assignment), kaya dito na rin bumaba ang outstanding balance at dito na
-- rin nagiging `completed` ang loan kapag fully paid na.
--
--   rider collect/submit
--     → payments.status = 'verified'
--     → collection_assignments.status = 'completed' (+ completed_at)
--     → agad bumababa ang loan balance (walang approval step)
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- 1) Notification type para sa informational na abiso sa staff (dating
--    'collection_pending_approval'). Kailangan itong naka-seed dahil ang
--    `notifications.type` ay may FK sa `notification_types(code)`.
INSERT INTO notification_types (code, label, sort_order) VALUES
  ('collection_collected', 'Rider Collection Collected', 35)
ON CONFLICT (code) DO NOTHING;

-- 2) Ang mga lumang `pending_approval` na row ay hindi na maa-approve (tinanggal
--    na ang approve/reject sa UI) — i-finalize na sila bilang `completed` para
--    hindi maiwang nakabinbin at para mabilang na sa loan balance ang bayad na
--    naitala na ng rider (`verified` ang payment nila).
UPDATE collection_assignments
SET status       = 'completed',
    completed_at = COALESCE(completed_at, NOW())
WHERE status = 'pending_approval';

-- 3) Dokumentasyon: legacy na ang status na ito (hindi na nagsi-set ang rider
--    submit nito), pero nananatili pa rin ang code para sa lumang audit rows.
UPDATE collection_assignment_statuses
SET description = 'Legacy: rider submission na naghihintay pa ng approval sa lumang flow (hindi na ginagamit)'
WHERE code = 'pending_approval';

COMMIT;
