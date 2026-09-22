-- Migration 00173: Seed notification_types para sa account-upgrade outcome
--
-- WHY: ang notifications.type ay may FK sa notification_types(code), pero ang
-- mga type na ipinapadala ng kyc-view?fn=verify sa lender ay HINDI naka-seed:
--
--   account_upgrade_verified  →  "Account Upgrade Verified"
--   account_upgrade_rejected  →  "Account Upgrade Rejected"
--
-- Kaya tuwing nag-re-reject (o nagbe-verify) ang head manager / employee ng
-- account upgrade submission, ang insert sa notifications ay nabigo sa FK
-- constraint at ang error lang ang naka-log ("Notification insert failed") —
-- silently swallowed, kaya WALANG notification (in-app man o FCM push) na
-- nakakarating sa lender. Kapareho ito ng dating bug ng 'payment_due' (00151).
--
-- Kasama na rin dito ang dalawang CI type na ginagamit ng ci-manage para sa
-- rider at lender (ci_approved / ci_rejected) — wala rin silang seed, kaya
-- FK violation din ang nangyayari sa "Investigation Report Approved / Needs
-- Revision" notifications.
--
-- Idempotent: ON CONFLICT (code) DO NOTHING, kaya safe i-rerun.

BEGIN;
SET search_path = public, extensions;

-- ── Account upgrade outcome (lender-facing) ─────────────────────────────────
INSERT INTO notification_types (code, label, sort_order) VALUES
  ('account_upgrade_verified', 'Account Upgrade Verified', 35),
  ('account_upgrade_rejected', 'Account Upgrade Rejected', 36)
ON CONFLICT (code) DO NOTHING;

-- ── CI outcome (rider + lender) ─────────────────────────────────────────────
INSERT INTO notification_types (code, label, sort_order) VALUES
  ('ci_approved', 'CI Approved', 37),
  ('ci_rejected', 'CI Rejected', 38)
ON CONFLICT (code) DO NOTHING;

COMMIT;
