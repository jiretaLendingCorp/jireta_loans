// supabase/functions/auth-login/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { errorResponse, handleCors, jsonResponse } from '../_shared/cors.ts';
import { getAdminClient, getAnonClient } from '../_shared/db.ts';
import { sanitizeString, validateEmail } from '../_shared/validators.ts';

const MAX_FAILED = 5;
const LOCKOUT_MINUTES = 15;

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const { email, password } = await req.json();
    if (!email || !password) return errorResponse('Email and password are required', 400, 'VALIDATION_ERROR');
    if (!validateEmail(sanitizeString(email))) return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const anonAuth = getAnonClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: user, error: userErr } = await db
      .from('users')
      .select('id, email, account_status, force_password_change, roles(name)')
      .eq('email', email.trim().toLowerCase())
      .single();

    if (userErr || !user) {
      return errorResponse('Invalid email or password', 401, 'INVALID_CREDENTIALS');
    }

    if (user.account_status === 'suspended') return errorResponse('Account suspended', 403, 'ACCOUNT_SUSPENDED');
    if (user.account_status === 'archived') return errorResponse('Account archived', 403, 'ACCOUNT_ARCHIVED');

    const role = (user as any).roles?.name;
    if (!['head_manager', 'employee'].includes(role)) {
      return errorResponse('Web login not available for this role', 403, 'FORBIDDEN');
    }

    const { data: recentLogs } = await db
      .from('auth_logs')
      .select('id, is_locked, created_at')
      .eq('user_id', user.id)
      .eq('event_type', 'login_fail')
      .gte('created_at', new Date(Date.now() - LOCKOUT_MINUTES * 60000).toISOString())
      .order('created_at', { ascending: false });

    const failCount = recentLogs?.length ?? 0;
    const isLocked = recentLogs?.some((l: any) => l.is_locked) ?? false;

    if (isLocked || failCount >= MAX_FAILED) {
      return errorResponse(`Account locked. Try again in ${LOCKOUT_MINUTES} minutes.`, 429, 'ACCOUNT_LOCKED');
    }

    const { data: authData, error: authErr } = await anonAuth.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password,
    });

    if (authErr || !authData.session) {
      const newFails = failCount + 1;
      await db.from('auth_logs').insert({
        user_id: user.id,
        event_type: 'login_fail',
        ip_address: ip,
        failed_attempts: newFails,
        is_locked: newFails >= MAX_FAILED,
      });
      return errorResponse('Invalid email or password', 401, 'INVALID_CREDENTIALS');
    }

    await db.from('auth_logs').insert({
      user_id: user.id,
      event_type: 'login_success',
      ip_address: ip,
      failed_attempts: 0,
      is_locked: false,
    });
    await db.from('users').update({ last_login_at: new Date().toISOString() }).eq('id', user.id);

    return jsonResponse({
      access_token: authData.session.access_token,
      refresh_token: authData.session.refresh_token,
      user: {
        id: user.id,
        email: user.email,
        role,
        force_password_change: user.force_password_change,
      },
    });
  } catch (err) {
    console.error('auth-login error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
