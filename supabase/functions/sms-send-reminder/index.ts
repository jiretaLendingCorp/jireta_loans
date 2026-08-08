// supabase/functions/sms-send-reminder/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sendSms } from '../_shared/sms.ts';
import { getSchedulePayment } from '../_shared/loan_financials.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
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
      const loan = (schedule as any).loan;
      if (!loan) continue;
      const lender = loan.lender;
      if (!lender?.phone_number) continue;

      const schedulePayment = await getSchedulePayment(db, (schedule as any).id);
      if (schedulePayment.amount_paid >= Number((schedule as any).amount_due)) continue;

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
  } catch (err) {
    console.error('sms-send-reminder error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});