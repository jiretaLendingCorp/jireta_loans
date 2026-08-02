// supabase/functions/_shared/rate_limiter.ts
import { getAdminClient } from './db.ts';

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