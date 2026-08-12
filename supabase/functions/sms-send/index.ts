// supabase/functions/sms-send/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   sms-send-otp      →  ?fn=send-otp
//   sms-send-reminder →  ?fn=send-reminder
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { sendSms } from '../_shared/sms.ts';
import { getAdminClient } from '../_shared/db.ts';
import { getSchedulePayment } from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'send-otp';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'send-otp':
        // ── [moved from functions/sms-send-otp/index.ts] ───────────────
        return await handleSendOtp(req);
      case 'send-reminder':
        // ── [moved from functions/sms-send-reminder/index.ts] ─────────
        return await handleSendReminder(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('sms-send error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/sms-send-otp/index.ts] ────────────────────────────
async function handleSendOtp(req: Request) {
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
}

// ── [moved from functions/sms-send-reminder/index.ts] ───────────────────────
async function handleSendReminder(_req: Request) {
  const db = getAdminClient();

  const targetDate = new Date();
  targetDate.setDate(targetDate.getDate() + 2);
  const targetDateStr = targetDate.toISOString().split('T')[0];

  const { data: dueSchedules, error } = await db
    .from('loan_schedules')
    .select(
      `id, due_date, amount_due,
       loan:loans!loan_schedules_loan_id_fkey(
         loan_number, status,
         lender_profiles!loans_lender_id_fkey(
           id,
           users!lender_profiles_id_fkey(id, first_name, last_name, phone_number)
         )
       )`
    )
    .eq('due_date', targetDateStr)
    .in('loan.status', ['active', 'overdue']);

  if (error) return errorResponse('Failed to fetch due schedules', 500, 'DB_ERROR');

  const results: Record<string, string>[] = [];

  for (const schedule of dueSchedules ?? []) {
    const loan = embedAsObject(schedule?.loan);
    if (!loan) continue;
    const lp = embedAsObject(loan.lender_profiles);
    const lender = lp ? embedAsObject(lp.users) : null;
    if (!lender?.phone_number) continue;

    const schedulePayment = await getSchedulePayment(db, schedule.id);
    if (schedulePayment.amount_paid >= Number(schedule.amount_due)) continue;

    const name = `${lender.first_name} ${lender.last_name}`;
    const amount = new Intl.NumberFormat('en-PH', {
      style: 'currency', currency: 'PHP',
    }).format(Number(schedule.amount_due));
    const message = `Hi ${name}, your Jireta Loans payment of ${amount} is due on ${targetDateStr} (Loan: ${loan.loan_number}). Pay on time to avoid penalties.`;

    const smsResult = await sendSms({ to: lender.phone_number, message, userId: lender.id, loanScheduleId: schedule.id });

    results.push({ phone: lender.phone_number, status: smsResult ? 'sent' : 'failed' });
  }

  return jsonResponse({
    success: true,
    reminders_sent: results.filter((r) => r.status === 'sent').length,
    reminders_failed: results.filter((r) => r.status === 'failed').length,
    target_date: targetDateStr,
  });
}