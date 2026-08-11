// supabase/functions/reports-generate/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { getLoanFinancialsBatch, getLoanDisbursementsBatch } from '../_shared/loan_financials.ts';

async function fetchReportData(
  db: ReturnType<typeof import('../_shared/db.ts').getAdminClient>,
  templateKey: string,
  params: Record<string, string>
): Promise<unknown[]> {
  const dateFrom = params.date_from;
  const dateTo = params.date_to;

  switch (templateKey) {
    case 'loan_report': {
      let q = db.from('loans').select(
        `id, loan_number, principal_amount, status, payment_frequency, created_at,
         lender:lender_profiles!loans_lender_id_fkey(id, users!lender_profiles_id_fkey(first_name, last_name, phone_number))`
      );
      if (params.status) q = q.eq('status', params.status);
      if (dateFrom) q = q.gte('created_at', dateFrom);
      if (dateTo) q = q.lte('created_at', dateTo);
      const { data } = await q;
      const rows = data ?? [];
      const [finMap, disbMap] = await Promise.all([
        getLoanFinancialsBatch(db, rows.map((r: any) => r.id)),
        getLoanDisbursementsBatch(db, rows.map((r: any) => r.id)),
      ]);
      return rows.map(({ id, ...r }: any) => {
        const fin = finMap[id] ?? {};
        const disb = disbMap[id] ?? null;
        return {
          ...r,
          total_payable: fin.total_payable ?? null,
          outstanding_balance: fin.outstanding_balance ?? null,
          disbursed_at: disb?.disbursed_at ?? null,
        };
      });
    }
    case 'payment_report': {
      let q = db.from('payments').select(
        `id, amount, payment_method, status, created_at,
         loan_schedule:loan_schedules(loan:loans(loan_number))`
      ).eq('status', 'verified');
      if (dateFrom) q = q.gte('created_at', dateFrom);
      if (dateTo) q = q.lte('created_at', dateTo);
      const { data } = await q;
      return (data ?? []).map((p: any) => {
        const schedule = p.loan_schedule ?? null;
        return {
          id: p.id,
          amount: p.amount,
          payment_method: p.payment_method,
          status: p.status,
          created_at: p.created_at,
          loan: schedule?.loan ?? null,
        };
      });
    }
    case 'collection_report': {
      let q = db.from('collection_assignments').select(
        `id, status, amount_collected, created_at,
         rider:rider_profiles(id, users!rider_profiles_id_fkey(first_name, last_name)),
         loan_schedule:loan_schedules(due_date, amount_due, loan:loans(loan_number))`
      );
      if (params.status) q = q.eq('status', params.status);
      if (dateFrom) q = q.gte('created_at', dateFrom);
      if (dateTo) q = q.lte('created_at', dateTo);
      const { data } = await q;
      return data ?? [];
    }
    case 'borrower_report': {
      const { data } = await db.from('users').select(
        `id, first_name, last_name, phone_number, account_status, created_at, roles!inner(name),
         lender_profiles(kyc_status, employment_type, monthly_income)`
      ).eq('roles.name', ROLES.LENDER);
      return data ?? [];
    }
    case 'overdue_report': {
      const { data } = await db.from('loans').select(
        `id, loan_number, principal_amount, created_at,
         lender:lender_profiles!loans_lender_id_fkey(id, users!lender_profiles_id_fkey(first_name, last_name, phone_number)),
         penalty_logs(penalty_amount, applied_at)`
      ).eq('status', 'overdue');
      const rows = data ?? [];
      const [finMap, disbMap] = await Promise.all([
        getLoanFinancialsBatch(db, rows.map((r: any) => r.id)),
        getLoanDisbursementsBatch(db, rows.map((r: any) => r.id)),
      ]);
      return rows.map(({ id, ...r }: any) => {
        const fin = finMap[id] ?? {};
        const disb = disbMap[id] ?? null;
        return {
          ...r,
          total_payable: fin.total_payable ?? null,
          outstanding_balance: fin.outstanding_balance ?? null,
          disbursed_at: disb?.disbursed_at ?? null,
        };
      });
    }
    case 'financial_report': {
      const { data: payments } = await db.from('payments')
        .select('amount, payment_method, created_at')
        .eq('status', 'verified')
        .gte('created_at', dateFrom ?? '2000-01-01')
        .lte('created_at', dateTo ?? new Date().toISOString());
      const { data: penalties } = await db.from('penalty_logs')
        .select('penalty_amount, applied_at')
        .gte('applied_at', dateFrom ?? '2000-01-01')
        .lte('applied_at', dateTo ?? new Date().toISOString());
      return [{ payments: payments ?? [], penalties: penalties ?? [] }];
    }
    case 'ci_report': {
      let q = db.from('credit_investigations').select(
        `id, status, created_at, completed_at, report_summary,
         rider:rider_profiles(id, users!rider_profiles_id_fkey(first_name, last_name)),
         loan:loans(loan_number, lender_profiles!loans_lender_id_fkey(users!lender_profiles_id_fkey(first_name, last_name)))`
      );
      if (dateFrom) q = q.gte('created_at', dateFrom);
      if (dateTo) q = q.lte('created_at', dateTo);
      const { data } = await q;
      return data ?? [];
    }
    case 'disbursement_report': {
      let q = db.from('disbursements').select(
        `id, method, amount, status, created_at,
         loan:loans(loan_number),
         disbursed_by_user:users!disbursements_authorized_by_fkey(first_name, last_name)`
      );
      if (dateFrom) q = q.gte('created_at', dateFrom);
      if (dateTo) q = q.lte('created_at', dateTo);
      const { data } = await q;
      return data ?? [];
    }
    default: {
      const { data } = await db.from('loans').select('*').limit(100);
      return data ?? [];
    }
  }
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { template_key, parameters } = body;

    if (!template_key) return errorResponse('template_key is required', 400, 'MISSING_FIELDS');

    const db = getAdminClient();

    const { data: template } = await db
      .from('report_templates')
      .select('id, template_key, title')
      .eq('template_key', template_key)
      .single();

    const reportData = await fetchReportData(db, template_key, parameters ?? {});

    const { data: report, error: reportErr } = await db
      .from('reports')
      .insert({
        report_type: template_key,
        title: template?.title ?? template_key,
        parameters: parameters ?? {},
        generated_by: authResult.id,
      })
      .select()
      .single();

    if (reportErr) return errorResponse('Failed to save report', 500, 'DB_ERROR');

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'report_export',
      tableName: 'reports',
      recordId: report.id,
      newValues: { template_key, parameters },
    });

    return jsonResponse({
      success: true,
      report_id: report.id,
      template_name: template?.title ?? template_key,
      row_count: Array.isArray(reportData) ? reportData.length : 1,
      data: reportData,
    });
  } catch (err) {
    console.error('reports-generate error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});