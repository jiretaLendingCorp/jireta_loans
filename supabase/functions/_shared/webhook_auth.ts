// supabase/functions/_shared/webhook_auth.ts
// ─────────────────────────────────────────────────────────────────────────────
// Validates the shared-secret header that pg_cron / pg_net send when a
// database function enqueues an edge function call (e.g. notifications-push
// from trg_notification_enqueue_push, sms-send from
// send_payment_due_reminders). One copy of the check so the two webhook
// entry points can never drift apart.
//
// The header value must match the PUSH_WEBHOOK_SECRET env var of the function
// being called; until that env var is set (or while it is still 'REPLACE_ME')
// every webhook call is refused.
// ─────────────────────────────────────────────────────────────────────────────

export async function isAuthorizedWebhook(req: Request): Promise<boolean> {
  const secret = req.headers.get('x-push-secret');
  if (!secret) return false;
  const expected = Deno.env.get('PUSH_WEBHOOK_SECRET');
  if (!expected || expected === 'REPLACE_ME') return false;
  // Constant-time-ish comparison for a shared secret.
  if (secret.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < secret.length; i++) {
    diff |= secret.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}
