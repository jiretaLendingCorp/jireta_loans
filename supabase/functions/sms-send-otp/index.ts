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

    const result = await sendSms(phone, message);
    if (!result.success) return errorResponse('Failed to send OTP SMS', 500, 'SMS_ERROR');

    const db = getAdminClient();
    await db.from('sms_logs').insert({
      phone_number: phone,
      message_type: 'otp',
      message_body: message,
      status: 'sent',
      provider_response: result.response ?? null,
    });

    return jsonResponse({ success: true });
  } catch (err) {
    console.error('sms-send-otp error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});