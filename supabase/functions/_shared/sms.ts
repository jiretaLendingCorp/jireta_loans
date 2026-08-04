// supabase/functions/_shared/sms.ts
import { getAdminClient } from './db.ts';

export async function sendSms(params: {
  to: string;
  message: string;
  userId?: string;
  loanScheduleId?: string;
}): Promise<boolean> {
  try {
    // DEV MOCK: when USE_MOCK_SMS is truthy, skip the real Semaphore call so
    // auth-send-otp (or any sender) never hangs waiting on the network. The
    // OTP code is overridden to 123456 in auth-send-otp. Remove this branch
    // / the env var to resume real SMS.
    if (Deno.env.get('USE_MOCK_SMS') === 'true') {
      console.log('[sms] MOCK_MODE: not sending real SMS to', params.to);
      if (params.userId) {
        const db = getAdminClient();
        await db.from('sms_logs').insert({
          user_id: params.userId,
          loan_schedule_id: params.loanScheduleId ?? null,
          phone_number: params.to,
          message: params.message,
          status: 'mocked',
          gateway_reference: null,
        });
      }
      return true;
    }

    const apiKey = Deno.env.get('SEMAPHORE_API_KEY');
    const senderName = Deno.env.get('SEMAPHORE_SENDER_NAME') ?? 'JiretaLoans';

    if (!apiKey) {
      console.warn('SEMAPHORE_API_KEY not configured');
      return false;
    }

    const body = new FormData();
    body.append('apikey', apiKey);
    body.append('number', params.to);
    body.append('message', params.message);
    body.append('sendername', senderName);

    const res = await fetch('https://api.semaphore.co/api/v4/messages', {
      method: 'POST',
      body,
    });

    const status = res.ok ? 'sent' : 'failed';
    const data = await res.json().catch(() => ({}));
    const gatewayRef = Array.isArray(data) ? data[0]?.message_id : null;

    if (params.userId) {
      const db = getAdminClient();
      await db.from('sms_logs').insert({
        user_id: params.userId,
        loan_schedule_id: params.loanScheduleId ?? null,
        phone_number: params.to,
        message: params.message,
        status,
        gateway_reference: gatewayRef ? String(gatewayRef) : null,
      });
    }

    return res.ok;
  } catch (err) {
    console.error('SMS send failed:', err);
    return false;
  }
}