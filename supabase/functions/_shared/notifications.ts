// supabase/functions/_shared/notifications.ts
// ─────────────────────────────────────────────────────────────────────────────
// Shared notification helpers used by every edge function that creates
// notifications (loans, CI, collections, payments, disbursements, KYC,
// in-office, users-create, webhooks, notifications-send, ...).
//
// The `notifications` table + Supabase Realtime remain the SOURCE OF TRUTH
// for in-app delivery. This module adds the FCM push channel on top:
//
//   insert notification row  →  atomically claim it (fcm_sent: false→true)
//                             →  send FCM HTTP v1 to the user's active
//                                device tokens (user_devices table)
//
// The atomic claim (UPDATE ... SET fcm_sent = true WHERE fcm_sent = false)
// guarantees each notification is pushed at most once, even when several
// dispatchers race (inline sends, the pg_net trigger webhook, view-function
// dispatch). Rows claimed by another dispatcher are simply skipped.
// ─────────────────────────────────────────────────────────────────────────────
import { getAdminClient } from './db.ts';
import { rowsWithObjectEmbeds } from './types.ts';
import { sendPushToUserDevices } from './fcm.ts';

/** Fields needed to compose a push from an existing notification row. */
export interface NotificationRowForPush {
  id: string;
  user_id: string;
  title: string;
  body: string;
  type: string;
  reference_id?: string | null;
}

/**
 * Atomically claims an unsent notification (fcm_sent false → true) and
 * returns the row. Returns null when the row does not exist or was already
 * claimed by another dispatcher. This is the duplicate-prevention gate.
 */
export async function claimNotification(
  db: ReturnType<typeof getAdminClient>,
  notificationId: string
): Promise<NotificationRowForPush | null> {
  const { data, error } = await db
    .from('notifications')
    .update({ fcm_sent: true })
    .eq('id', notificationId)
    .eq('fcm_sent', false)
    .select('id, user_id, title, body, type, reference_id')
    .maybeSingle();

  if (error) {
    console.error('[notifications] claim failed:', error.message);
    return null;
  }
  return (data as NotificationRowForPush | null) ?? null;
}

/** Claims a batch of the oldest unsent notifications (at most once each). */
export async function claimPendingNotifications(
  db: ReturnType<typeof getAdminClient>,
  limit = 50
): Promise<NotificationRowForPush[]> {
  const { data: candidates } = await db
    .from('notifications')
    .select('id')
    .eq('fcm_sent', false)
    .order('created_at', { ascending: true })
    .limit(limit);

  if (!candidates || candidates.length === 0) return [];

  const ids = candidates.map((c) => c.id as string);
  const { data: claimed, error } = await db
    .from('notifications')
    .update({ fcm_sent: true })
    .in('id', ids)
    .eq('fcm_sent', false)
    .select('id, user_id, title, body, type, reference_id');

  if (error) {
    console.error('[notifications] batch claim failed:', error.message);
    return [];
  }
  return (claimed as NotificationRowForPush[]) ?? [];
}

/** Claims + pushes an existing notification row (used by notifications-send
 *  and the notifications-push webhook). */
export async function claimAndSendPush(notificationId: string): Promise<void> {
  const db = getAdminClient();
  const row = await claimNotification(db, notificationId);
  if (!row) return; // not found or already claimed elsewhere
  await sendPushToUserDevices({
    userId: row.user_id,
    title: row.title,
    body: row.body,
    type: row.type,
    referenceId: row.reference_id ?? undefined,
    notificationId: row.id,
  });
}

/** Dispatches up to [limit] pending (unclaimed) notifications. Safe to call
 *  from any server context — rows claimed by another dispatcher are skipped. */
export async function dispatchPendingPushNotifications(
  limit = 50
): Promise<{ dispatched: number }> {
  const db = getAdminClient();
  const rows = await claimPendingNotifications(db, limit);
  if (rows.length === 0) return { dispatched: 0 };

  await Promise.all(
    rows.map((row) =>
      sendPushToUserDevices({
        userId: row.user_id,
        title: row.title,
        body: row.body,
        type: row.type,
        referenceId: row.reference_id ?? undefined,
        notificationId: row.id,
      })
    )
  );

  return { dispatched: rows.length };
}

export async function sendPushNotification(params: {
  userId: string;
  title: string;
  body: string;
  type: string;
  referenceId?: string;
  sentBy?: string;
}): Promise<void> {
  try {
    const db = getAdminClient();

    // 1) Source of truth: store the notification (in-app/Realtime delivery).
    const { data: inserted, error } = await db
      .from('notifications')
      .insert({
        user_id: params.userId,
        title: params.title,
        body: params.body,
        type: params.type,
        reference_id: params.referenceId ?? null,
        triggered_by: params.sentBy ?? null,
        is_read: false,
        sent_at: new Date().toISOString(),
      })
      .select('id')
      .single();
    if (error) {
      console.error('Notification insert failed:', error.message);
      return;
    }

    // 2) Claim the row so no other dispatcher (pg_net trigger webhook, view
    //    function sweep) pushes the same notification twice.
    const claimed = await claimNotification(db, inserted.id);
    if (!claimed) return; // already claimed by the webhook — it will push

    // 3) Additional delivery channel: FCM push to every active device.
    await sendPushToUserDevices({
      userId: params.userId,
      title: params.title,
      body: params.body,
      type: params.type,
      referenceId: params.referenceId ?? undefined,
      notificationId: claimed.id,
    });
  } catch (err) {
    console.error('Push notification failed:', err);
  }
}

export async function notifyStaff(params: {
  title: string;
  body: string;
  type: string;
  referenceId?: string;
  sentBy?: string;
}): Promise<void> {
  try {
    const db = getAdminClient();
    const { data: users } = await db
      .from('users')
      .select('id, roles!users_role_id_fkey(name)')
      .eq('account_status', 'active');

    const staff = (rowsWithObjectEmbeds(users) ?? []).filter(
      (u) => u?.roles?.name === 'head_manager' || u?.roles?.name === 'employee'
    );
    if (staff.length === 0) return;
    await Promise.all(
      staff.map((u) => sendPushNotification({ ...params, userId: u.id }))
    );
  } catch (err) {
    console.error('Notify staff failed:', err);
  }
}