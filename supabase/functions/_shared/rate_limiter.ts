// supabase/functions/_shared/rate_limiter.ts
import { getAdminClient } from './db.ts';

export type BlockInfo = {
  blocked: boolean;
  reason?: string;
  expiresAt?: string;
  retryAfterSeconds?: number;
};

/**
 * Sliding-window rate limit backed by `rate_limit_logs`. Counts requests with
 * the same `key` inside `windowMinutes` and, while under the limit, records
 * the attempt. Used for coarse throttling (e.g. "20 login attempts per
 * minute").
 */
export async function checkRateLimit(params: {
  key: string;
  maxAttempts: number;
  windowMinutes: number;
}): Promise<{ allowed: boolean; remaining: number }> {
  const db = getAdminClient();
  const windowStart = new Date(Date.now() - params.windowMinutes * 60 * 1000).toISOString();

  const { count } = await db
    .from('rate_limit_logs')
    .select('*', { count: 'exact', head: true })
    .eq('key', params.key)
    .gte('created_at', windowStart);

  const attempts = count ?? 0;
  const allowed = attempts < params.maxAttempts;

  if (allowed) {
    await db.from('rate_limit_logs').insert({ key: params.key });
    await db
      .from('rate_limit_logs')
      .delete()
      .lt('created_at', windowStart);
  }

  return { allowed, remaining: Math.max(0, params.maxAttempts - attempts - 1) };
}

/**
 * Checks whether `key` is currently blocked by an active security block
 * (see `blockKey`). Blocks persist in `security_blocks` until `expires_at`.
 */
export async function checkBlock(key: string): Promise<BlockInfo> {
  const db = getAdminClient();
  const now = new Date().toISOString();

  const { data } = await db
    .from('security_blocks')
    .select('reason, expires_at')
    .eq('key', key)
    .gt('expires_at', now)
    .order('expires_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!data) return { blocked: false };

  const expiresAt = data.expires_at as string;
  const retryAfterSeconds = Math.max(
    1,
    Math.ceil((new Date(expiresAt).getTime() - Date.now()) / 1000),
  );
  return {
    blocked: true,
    reason: data.reason ?? 'blocked',
    expiresAt,
    retryAfterSeconds,
  };
}

/**
 * Places a temporary block on `key` for `minutes`. All existing blocks for the
 * key are cleared first (a single, fresh expiry wins).
 */
export async function blockKey(params: {
  key: string;
  reason: string;
  minutes: number;
}): Promise<void> {
  const db = getAdminClient();
  await db.from('security_blocks').delete().eq('key', params.key);
  await db.from('security_blocks').insert({
    key: params.key,
    reason: params.reason,
    expires_at: new Date(Date.now() + params.minutes * 60 * 1000).toISOString(),
  });
}

/**
 * Records a suspicious-activity event into `security_events` for the head
 * manager / audit trail. Never throws — logging must not take down the
 * request path it is auditing.
 */
export async function recordSecurityEvent(params: {
  eventType: string;
  key: string;
  userId?: string | null;
  ipAddress?: string | null;
  detail?: Record<string, unknown> | null;
}): Promise<void> {
  try {
    const db = getAdminClient();
    await db.from('security_events').insert({
      event_type: params.eventType,
      key: params.key,
      user_id: params.userId ?? null,
      ip_address: params.ipAddress ?? null,
      detail: params.detail ?? null,
    });
  } catch (err) {
    console.error('[security] failed to record security event:', err);
  }
}

/**
 * Convenience guard for high-frequency abuse points: checks the sliding-window
 * count, and when the limit is breached it places a block and records a
 * security event. Returns the block info if the caller should stop.
 */
export async function guardRateLimit(params: {
  key: string;
  maxAttempts: number;
  windowMinutes: number;
  blockMinutes?: number;
  blockReason?: string;
  eventType?: string;
  userId?: string | null;
  ipAddress?: string | null;
}): Promise<{ allowed: boolean; remaining: number; block?: BlockInfo }> {
  const existingBlock = await checkBlock(params.key);
  if (existingBlock.blocked) {
    return { allowed: false, remaining: 0, block: existingBlock };
  }

  const { allowed, remaining } = await checkRateLimit({
    key: params.key,
    maxAttempts: params.maxAttempts,
    windowMinutes: params.windowMinutes,
  });

  if (!allowed) {
    const blockMinutes = params.blockMinutes ?? 15;
    await blockKey({
      key: params.key,
      reason: params.blockReason ?? 'rate limit exceeded',
      minutes: blockMinutes,
    });
    await recordSecurityEvent({
      eventType: params.eventType ?? 'rate_limit_exceeded',
      key: params.key,
      userId: params.userId ?? null,
      ipAddress: params.ipAddress ?? null,
    });
    const block = await checkBlock(params.key);
    return { allowed: false, remaining: 0, block };
  }

  return { allowed: true, remaining };
}