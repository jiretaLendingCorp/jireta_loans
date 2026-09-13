-- Migration 00155: `completed_at` only when the collection is really completed
--
-- Business rule:
--   `completed_at` = oras ng tunay na pagkatapos ng koleksyon (status =
--   'completed', pagkatapos ma-upload ang proof sa `fn=upload-proof`).
--
--   Dati, sine-set din ito ng `fn=record` sa collections-manage kahit amount pa
--   lang ang naitala (status = 'in_progress'). Kaya lumalabas sa Head Manager /
--   Employee ang "Completed At" na timestamp kahit hindi pa tapos ang
--   koleksyon, at tumutugma ito sa maling "Completed" na label sa rider app.
--
--   Inayos na sa backend (hindi na nagse-set ng completed_at ang record step).
--   Nililinis lang ng migration na ito ang mga lumang row na nauna nang
--   na-timestamp pero hindi naman talaga completed.
BEGIN;
SET search_path = public, extensions;

-- Ang `completed_at` ay may halaga lang kapag `status = 'completed'`.
-- (Ang CHECK na `collection_assignments_completed_requires_completed_at` ay
--  nananatiling valid: status = 'completed' -> may completed_at.)
UPDATE collection_assignments
   SET completed_at = NULL
 WHERE status <> 'completed'
   AND completed_at IS NOT NULL;

COMMIT;
