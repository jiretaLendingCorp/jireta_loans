// supabase/functions/_shared/notifications.ts
import { getAdminClient } from './db.ts';
import { rowsWithObjectEmbeds } from './types.ts';

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
    const { data: user } = await db
      .from('users')
      .select('fcm_token')
      .eq('id', params.userId)
      .single();

    const { error } = await db.from('notifications').insert({
      user_id: params.userId,
      title: params.title,
      body: params.body,
      type: params.type,
      reference_id: params.referenceId ?? null,
      triggered_by: params.sentBy ?? null,
      is_read: false,
      sent_at: new Date().toISOString(),
    });
    if (error) {
      console.error('Notification insert failed:', error.message);
    }

    if (user?.fcm_token) {
      const fcmKey = Deno.env.get('FCM_SERVER_KEY');
      if (!fcmKey) return;

      // Bound the FCM call so a slow/unreachable FCM endpoint can never hang
      // the caller's request response (the DB row is already written above).
      await fetch('https://fcm.googleapis.com/fcm/send', {
        method: 'POST',
        headers: {
          Authorization: `key=${fcmKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          to: user.fcm_token,
          notification: { title: params.title, body: params.body },
          data: { type: params.type, reference_id: params.referenceId ?? '' },
        }),
        signal: AbortSignal.timeout(5000),
      });
    }
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
      .select('id, roles(name)')
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