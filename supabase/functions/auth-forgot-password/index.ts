// supabase/functions/auth-forgot-password/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validateEmail, sanitizeString } from '../_shared/validators.ts';
import { checkRateLimit } from '../_shared/rate_limiter.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const { email } = await req.json();
    if (!email) return errorResponse('Email is required', 400, 'VALIDATION_ERROR');

    const cleanEmail = sanitizeString(email).toLowerCase();
    if (!validateEmail(cleanEmail)) return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');

    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const { allowed } = await checkRateLimit({
      key: `forgot_password:${cleanEmail}`,
      maxAttempts: 3,
      windowMinutes: 15,
    });
    if (!allowed) return errorResponse('Too many requests. Try again in 15 minutes.', 429, 'RATE_LIMITED');

    const db = getAdminClient();

    const { data: user } = await db
      .from('users')
      .select('id, account_status, roles!inner(name)')
      .eq('email', cleanEmail)
      .single();

    if (!user || !['head_manager', 'employee'].includes((user as any).roles?.name)) {
      return jsonResponse({ message: 'If that email is registered, a reset link has been sent.' });
    }

    if (user.account_status !== 'active') {
      return jsonResponse({ message: 'If that email is registered, a reset link has been sent.' });
    }

    const { error } = await db.auth.resetPasswordForEmail(cleanEmail, {
      redirectTo: `${Deno.env.get('APP_URL') ?? 'https://app.jiretaloanscorp.com'}/reset-password`,
    });

    if (!error) {
      await db.from('auth_logs').insert({
        user_id: user.id,
        event_type: 'password_reset_requested',
        ip_address: ip,
      });
    }

    return jsonResponse({ message: 'If that email is registered, a reset link has been sent.' });
  } catch (err) {
    console.error('auth-forgot-password error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});