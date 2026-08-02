// supabase/functions/auth-verify-otp/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePhone, sanitizeString } from '../_shared/validators.ts';

const MAX_OTP_ATTEMPTS = 5;

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const { phone_number, code } = await req.json();
    const phone = sanitizeString(String(phone_number ?? ''));
    const otpCode = sanitizeString(String(code ?? ''));

    if (!validatePhone(phone)) return errorResponse('Invalid phone number', 400, 'VALIDATION_ERROR');
    if (!/^\d{6}$/.test(otpCode)) return errorResponse('OTP must be 6 digits', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();

    const { data: otpRow } = await db
      .from('otp_codes')
      .select('*')
      .eq('phone_number', phone)
      .eq('used', false)
      .gte('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
      .single();

    if (!otpRow) return errorResponse('OTP expired or not found', 401, 'OTP_EXPIRED');

    if (otpRow.attempts >= MAX_OTP_ATTEMPTS) {
      await db.from('otp_codes').update({ used: true }).eq('id', otpRow.id);
      return errorResponse('Too many attempts. Request a new OTP.', 429, 'RATE_LIMITED');
    }

    if (otpRow.code !== otpCode) {
      await db.from('otp_codes').update({ attempts: otpRow.attempts + 1 }).eq('id', otpRow.id);
      return errorResponse('Invalid OTP code', 401, 'INVALID_OTP');
    }

    await db.from('otp_codes').update({ used: true }).eq('id', otpRow.id);

    const { data: user } = await db
      .from('users')
      .select('id, account_status, email, force_password_change, roles(name)')
      .eq('phone_number', phone)
      .single();

    if (!user) return errorResponse('User not found', 404, 'NOT_FOUND');

    const { data: authData, error: authErr } = await db.auth.signInWithOtp({
      phone: phone.replace(/^0/, '+63'),
    });

    const { data: adminAuth } = await db.auth.admin.generateLink({
      type: 'magiclink',
      email: user.email ?? `${phone}@jireta.temp`,
    });

    const phoneEmail = `${phone}@jireta-loans.app`;
    let session = null;
    
    const { data: signIn } = await db.auth.signInWithPassword({
      email: phoneEmail,
      password: `OTP_${phone}_SECURE`,
    }).catch(() => ({ data: null }));
    
    if (signIn?.session) {
      session = signIn.session;
    } else {
      const { data: created } = await db.auth.admin.createUser({
        email: phoneEmail,
        password: `OTP_${phone}_SECURE`,
        email_confirm: true,
        user_metadata: { user_id: user.id, role: (user as any).roles?.name },
      });
      if (created?.user) {
        const { data: s2 } = await db.auth.signInWithPassword({
          email: phoneEmail,
          password: `OTP_${phone}_SECURE`,
        });
        session = s2?.session;
      }
    }

    if (!session) {
      const { data: customToken } = await db.auth.admin.generateLink({
        type: 'magiclink',
        email: phoneEmail,
      });
      return jsonResponse({
        access_token: customToken?.properties?.hashed_token ?? '',
        refresh_token: '',
        user: {
          id: user.id,
          phone,
          role: (user as any).roles?.name,
          force_password_change: user.force_password_change,
        },
      });
    }

    await db.from('auth_logs').insert({
      user_id: user.id,
      event_type: 'login_success',
      ip_address: req.headers.get('x-forwarded-for') ?? 'unknown',
    });
    await db.from('users').update({ last_login_at: new Date().toISOString() }).eq('id', user.id);

    return jsonResponse({
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      user: {
        id: user.id,
        phone,
        role: (user as any).roles?.name,
        force_password_change: user.force_password_change,
      },
    });
  } catch (err) {
    console.error('auth-verify-otp error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});