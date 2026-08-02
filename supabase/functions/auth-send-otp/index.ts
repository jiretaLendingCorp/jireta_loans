// supabase/functions/auth-send-otp/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePhone, sanitizeString } from '../_shared/validators.ts';
import { sendSms } from '../_shared/sms.ts';

const OTP_RATE_LIMIT = 3;
const OTP_WINDOW_MINUTES = 5;
const OTP_EXPIRY_MINUTES = 10;

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const { phone_number } = await req.json();
    const phone = sanitizeString(String(phone_number ?? ''));

    if (!validatePhone(phone)) return errorResponse('Invalid Philippine phone number (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();

    const { data: user } = await db
      .from('users')
      .select('id, account_status, roles(name)')
      .eq('phone_number', phone)
      .single();

    if (!user) return errorResponse('Phone number not registered', 404, 'NOT_FOUND');
    if (user.account_status === 'suspended') return errorResponse('Account suspended', 403, 'ACCOUNT_SUSPENDED');
    if (user.account_status === 'archived') return errorResponse('Account archived', 403, 'ACCOUNT_ARCHIVED');

    const role = (user as any).roles?.name;
    if (!['rider', 'lender'].includes(role)) return errorResponse('OTP login not available for this role', 403, 'FORBIDDEN');

    const windowStart = new Date(Date.now() - OTP_WINDOW_MINUTES * 60000).toISOString();
    const { count } = await db
      .from('otp_codes')
      .select('*', { count: 'exact', head: true })
      .eq('phone_number', phone)
      .gte('created_at', windowStart);

    if ((count ?? 0) >= OTP_RATE_LIMIT) {
      return errorResponse(`OTP limit reached. Wait ${OTP_WINDOW_MINUTES} minutes.`, 429, 'RATE_LIMITED');
    }

    await db.from('otp_codes').update({ used: true }).eq('phone_number', phone).eq('used', false);

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60000).toISOString();

    await db.from('otp_codes').insert({
      phone_number: phone,
      code,
      expires_at: expiresAt,
      attempts: 0,
      used: false,
    });

    const message = `Your Jireta Loans OTP is: ${code}. Valid for ${OTP_EXPIRY_MINUTES} minutes. Do not share this code.`;
    await sendSms({ to: phone, message, userId: user.id });

    await db.from('auth_logs').insert({
      user_id: user.id,
      event_type: 'otp_sent',
      ip_address: req.headers.get('x-forwarded-for') ?? 'unknown',
    });

    return jsonResponse({ message: 'OTP sent successfully', expires_in: OTP_EXPIRY_MINUTES * 60 });
  } catch (err) {
    console.error('auth-send-otp error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});