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
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { isAuthorizedWebhook } from '../_shared/webhook_auth.ts';
import { getSchedulePayment } from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';

// Manila (UTC+8) date string N days from today, as YYYY-MM-DD.
// Date#toISOString() is UTC, so it cannot be used directly for a Manila
// business date — in the 00:00–08:00 Manila window it returns YESTERDAY.
const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
function manilaDatePlusDays(days: number): string {
  const d = new Date(Date.now() + MANILA_OFFSET_MS);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().split('T')[0];
}

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
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const body = await req.json();
  const { phone, otp } = body;

  if (!phone || !otp) return errorResponse('phone and otp are required', 400, 'MISSING_FIELDS');

  const message = `Your Jireta Loans OTP is: ${otp}. Valid for 1 minute. Do not share this code.`;

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
async function handleSendReminder(req: Request) {
  // Two callers:
  //   1) pg_cron → pg_net webhook with the x-push-secret header — this is the
  //      automatic daily run scheduled by migration 00151.
  //   2) A logged-in HM/Employee (JWT) — manual trigger.
  const authResult = await requireAuth(req).catch(() => null);
  const authorizedAsStaff = authResult !== null &&
    isAuthUser(authResult) &&
    requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE) === null;
  if (!authorizedAsStaff && !(await isAuthorizedWebhook(req))) {
    return errorResponse('Unauthorized', 401, 'UNAUTHORIZED');
  }

  const db = getAdminClient();

  // Days before the due date, from system_config (default 2).
  let reminderDays = 2;
  const { data: cfg } = await db
    .from('system_config')
    .select('config_value')
    .eq('config_key', 'payment_reminder_days')
    .maybeSingle();
  const parsedDays = Number(cfg?.config_value);
  if (Number.isFinite(parsedDays) && parsedDays >= 0) {
    reminderDays = Math.floor(parsedDays);
  }

  const targetDateStr = manilaDatePlusDays(reminderDays);

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
    const message = `Hello ${name}, this is a friendly reminder that your Jireta Loans payment of ${amount} is due on ${targetDateStr} (Loan: ${loan.loan_number}). Please pay on time to avoid penalties. Thank you!`;

    const smsResult = await sendSms({ to: lender.phone_number, message, userId: lender.id, loanScheduleId: schedule.id });

    // In-app + push notification. migration 00151's
    // send_payment_due_reminders() is the primary inserter; only insert here
    // when no 'payment_due' notification exists for this schedule yet, so the
    // DB sweep and this function can never produce a duplicate.
    try {
      const { count } = await db
        .from('notifications')
        .select('id', { count: 'exact', head: true })
        .eq('type', 'payment_due')
        .eq('reference_id', schedule.id)
        .eq('user_id', lender.id);
      if ((count ?? 0) === 0) {
        const { sendPushNotification } = await import('../_shared/notifications.ts');
        await sendPushNotification({
          userId: lender.id,
          title: `Payment Due in ${reminderDays} Days`,
          body: `Hello ${name}, your payment of ${amount} for loan ${loan.loan_number} is due on ${targetDateStr}. Please pay on time to avoid penalties. Tap to view details.`,
          type: 'payment_due',
          referenceId: schedule.id,
        });
      }
    } catch (_) {}

    results.push({ phone: lender.phone_number, status: smsResult ? 'sent' : 'failed' });
  }

  return jsonResponse({
    success: true,
    reminders_sent: results.filter((r) => r.status === 'sent').length,
    reminders_failed: results.filter((r) => r.status === 'failed').length,
    target_date: targetDateStr,
  });
}