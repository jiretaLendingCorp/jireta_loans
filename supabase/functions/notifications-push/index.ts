// supabase/functions/notifications-push/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Push dispatcher for notifications that were created OUTSIDE the shared
// sendPushNotification() helper — e.g. overdue notifications inserted by the
// expire_overdue_assignments() DB function (00114) or any future SQL-side
// insert. The pg_net trigger (00126) posts here with the notification id;
// the function re-reads the row, atomically claims it (fcm_sent false→true)
// so it is pushed at most once, and sends via FCM HTTP v1.
//
//   ?fn=send&id=<notification_id>   — webhook: requires x-push-secret header
//                                     matching PUSH_WEBHOOK_SECRET, OR a valid
//                                     user JWT.
//   ?fn=dispatch-pending            — sweeps oldest unclaimed notifications
//                                     (requires a valid user JWT).
//
// No secrets are ever returned in responses; failure is always non-fatal.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { getAdminClient } from '../_shared/db.ts';
import { claimNotification, dispatchPendingPushNotifications } from '../_shared/notifications.ts';
import { sendPushToUserDevices } from '../_shared/fcm.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? 'send';
    switch (fn) {
      case 'send':
        return await handleSend(req);
      case 'dispatch-pending':
        return await handleDispatchPending(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('notifications-push error:', err instanceof Error ? err.message : err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

async function isAuthorizedWebhook(req: Request): Promise<boolean> {
  const secret = req.headers.get('x-push-secret');
  if (!secret) return false;
  const expected = Deno.env.get('PUSH_WEBHOOK_SECRET');
  if (!expected || expected === 'REPLACE_ME') return false;
  // Constant-time-ish comparison for a shared secret.
  if (secret.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < secret.length; i++) diff |= secret.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

/** Pushes a single existing notification row by id (webhook entry point). */
async function handleSend(req: Request) {
  const id = new URL(req.url).searchParams.get('id');
  if (!id) return errorResponse('id query param required', 400, 'MISSING_ID');

  // Accept either the pg_net webhook secret or a valid user JWT.
  const authResult = await requireAuth(req).catch(() => null);
  const authenticated =
    (authResult !== null && isAuthUser(authResult)) ||
    (await isAuthorizedWebhook(req));
  if (!authenticated) {
    return errorResponse('Unauthorized', 401, 'UNAUTHORIZED');
  }

  // Atomically claim — if another dispatcher already pushed it, skip quietly.
  const db = getAdminClient();
  const row = await claimNotification(db, id);
  if (!row) {
    return jsonResponse({ success: true, claimed: false });
  }

  const result = await sendPushToUserDevices({
    userId: row.user_id,
    title: row.title,
    body: row.body,
    type: row.type,
    referenceId: row.reference_id ?? undefined,
    notificationId: row.id,
  });

  return jsonResponse({ success: true, claimed: true, sent: result.sent, failed: result.failed, deactivated: result.deactivated });
}

/** Sweeps the oldest unclaimed notifications and pushes them (JWT only). */
async function handleDispatchPending(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;

  const { dispatched } = await dispatchPendingPushNotifications(50);
  return jsonResponse({ success: true, dispatched });
}