// supabase/functions/_shared/fcm.ts
// ─────────────────────────────────────────────────────────────────────────────
// Firebase Cloud Messaging HTTP v1 sender — server-side ONLY.
//
//   Secrets (set as Supabase Edge Function secrets / env vars):
//     FIREBASE_PROJECT_ID      — Firebase project id
//     FIREBASE_CLIENT_EMAIL    — service account client email
//     FIREBASE_PRIVATE_KEY     — service account private key (PKCS#8 PEM)
//
//   Security rules honored here:
//     - Firebase credentials are read from env vars only, never from the
//       request body, headers, or any client-supplied input.
//     - The OAuth access token is generated and cached in-process; it is
//       never returned to callers or logged.
//     - Logs never include tokens, keys, or device tokens.
//
//   The FCM OAuth 2.0 flow: sign a JWT with the service-account private key
//   (RS256), exchange it at https://oauth2.googleapis.com/token for a
//   short-lived access token, then call the HTTP v1 endpoint
//   POST https://fcm.googleapis.com/v1/projects/{project}/messages:send
//   once per device token.
// ─────────────────────────────────────────────────────────────────────────────
import { getAdminClient } from './db.ts';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FCM_V1_URL = (projectId: string): string =>
  `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`;

interface CachedAccessToken {
  token: string;
  expiresAt: number;
}

let cachedToken: CachedAccessToken | null = null;

// ── base64 helpers ──────────────────────────────────────────────────────────

export function toBase64Url(input: string | Uint8Array): string {
  const bytes =
    typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** PKCS#8 PEM → DER bytes. Tolerates literal `\n` escapes that Supabase
 *  secrets editors sometimes store instead of real newlines. */
export function pemToDer(pem: string): ArrayBuffer {
  const normalized = pem.replace(/\\n/g, '\n');
  const base64Body = normalized
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  const binary = atob(base64Body);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

// ── OAuth 2.0 access token (cached) ─────────────────────────────────────────

export async function getFcmAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.token;
  }

  const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL');
  const privateKey = Deno.env.get('FIREBASE_PRIVATE_KEY');
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID');

  if (!clientEmail || !privateKey || !projectId) {
    throw new Error(
      '[fcm] FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY and FIREBASE_PROJECT_ID must be configured as server-side secrets'
    );
  }

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: clientEmail,
    scope: FCM_SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };

  const signingInput =
    `${toBase64Url(JSON.stringify(header))}.${toBase64Url(JSON.stringify(claims))}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      key,
      new TextEncoder().encode(signingInput)
    )
  );
  const assertion = `${signingInput}.${toBase64Url(signature)}`;

  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
    signal: AbortSignal.timeout(5000),
  });

  if (!res.ok) {
    // Never include the assertion (it embeds credentials) in logs.
    const snippet = (await res.text().catch(() => '')).slice(0, 200);
    console.error('[fcm] OAuth access token request failed', res.status, snippet);
    throw new Error(`[fcm] failed to obtain OAuth access token (status ${res.status})`);
  }

  const data = await res.json() as { access_token?: string; expires_in?: number };
  if (!data.access_token) {
    throw new Error('[fcm] OAuth response missing access_token');
  }

  const expiresIn = (data.expires_in ?? 3600) - 60; // 60s clock-skew buffer
  cachedToken = { token: data.access_token, expiresAt: Date.now() + expiresIn * 1000 };
  return cachedToken.token;
}

// ── Sending ─────────────────────────────────────────────────────────────────

export interface FcmNotificationPayload {
  userId: string;
  title: string;
  body: string;
  type: string;
  referenceId?: string;
  notificationId?: string;
}

export interface FcmSendResult {
  sent: number;
  failed: number;
  deactivated: number;
}

/**
 * Sends a push notification to every ACTIVE device token of [userId] using
 * the FCM HTTP v1 API. Invalid/expired tokens (UNREGISTERED, invalid
 * argument, sender mismatch) are deactivated so they are not retried.
 *
 * This is an additional delivery channel only — the caller must have
 * already written the notification row (the existing in-app/Realtime
 * system remains the source of truth).
 */
export async function sendPushToUserDevices(
  params: FcmNotificationPayload
): Promise<FcmSendResult> {
  const result: FcmSendResult = { sent: 0, failed: 0, deactivated: 0 };

  try {
    const db = getAdminClient();
    const { data: devices, error: devErr } = await db
      .from('user_devices')
      .select('id, fcm_token')
      .eq('user_id', params.userId)
      .eq('is_active', true);

    if (devErr) {
      console.error('[fcm] device lookup failed:', devErr.message);
      return result;
    }
    if (!devices || devices.length === 0) return result;

    const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
    if (!projectId) {
      console.error('[fcm] FIREBASE_PROJECT_ID not configured');
      return result;
    }

    const accessToken = await getFcmAccessToken();

    await Promise.all(
      devices.map(async (device) => {
        try {
          const res = await fetch(FCM_V1_URL(projectId), {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              message: {
                token: device.fcm_token,
                notification: {
                  title: params.title,
                  body: params.body,
                },
                data: {
                  type: params.type,
                  reference_id: params.referenceId ?? '',
                  notification_id: params.notificationId ?? '',
                },
                android: { priority: 'high' },
                apns: { headers: { 'apns-priority': '10' } },
              },
            }),
            signal: AbortSignal.timeout(5000),
          });

          if (res.ok) {
            result.sent++;
            return;
          }

          // ── Token-level failures → deactivate so we stop retrying ──
          const body = await res.json().catch(() => ({})) as {
            error?: { status?: string; message?: string; details?: Array<{ errorCode?: string }> };
          };
          const errorCode = body?.error?.details?.[0]?.errorCode ?? body?.error?.status ?? '';
          const reason = body?.error?.message ?? '';
          const detail = JSON.stringify({ errorCode, reason });

          if (res.status === 404 || res.status === 400) {
            const isInvalidToken =
              /UNREGISTERED|INVALID_ARGUMENT|registration-token-not-found|MISMATCH_SENDER_ID|sender-id-mismatch/i.test(
                detail
              );
            if (isInvalidToken) {
              await db
                .from('user_devices')
                .update({ is_active: false })
                .eq('id', device.id);
              result.deactivated++;
              return;
            }
          }

          console.error('[fcm] send failed (non-fatal):', res.status, reason || errorCode);
          result.failed++;
        } catch (err) {
          console.error(
            '[fcm] send exception (non-fatal):',
            err instanceof Error ? err.message : String(err)
          );
          result.failed++;
        }
      })
    );
  } catch (err) {
    console.error(
      '[fcm] sendPushToUserDevices error:',
      err instanceof Error ? err.message : String(err)
    );
  }

  return result;
}