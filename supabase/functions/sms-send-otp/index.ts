// supabase/functions/sms-send-otp/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { sendSms } from '../_shared/sms.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const body = await req.json();
    const { phone, otp } = body;

    if (!phone || !otp) return errorResponse('phone and otp are required', 400, 'MISSING_FIELDS');

    const message = `Your Jireta Loans OTP is: ${otp}. Valid for 5 minutes. Do not share this code.`;

    const result = await sendSms({ to: phone, message });
    if (!result) return errorResponse('Failed to send OTP SMS', 500, 'SMS_ERROR');

    const db = getAdminClient();
    const { data: user } = await db
      .from('users')
      .select('id')
      .eq('phone_number', phone)
      .maybeSingle();

    await db.from('sms_logs').insert({
      user_id: user?.id,
      phone_number: phone,
      message,
      status: 'sent',
      gateway_reference: null,
    });

    return jsonResponse({ success: true });
  } catch (err) {
    console.error('sms-send-otp error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});