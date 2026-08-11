// supabase/functions/reports-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   reports-get-list     →  ?fn=get-list
//   reports-get-history  →  ?fn=get-history
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { embedAsObject } from '../_shared/types.ts';

// ── [moved from reports-get-list] ───────────────────────────────────────────
const REPORT_TEMPLATES = [
  { key: 'loan_report', name: 'Loan Report', description: 'All loan applications with status breakdown', category: 'Loans' },
  { key: 'payment_report', name: 'Payment Report', description: 'All verified payments with method breakdown', category: 'Payments' },
  { key: 'collection_report', name: 'Collection Report', description: 'Rider collection assignments and outcomes', category: 'Collections' },
  { key: 'borrower_report', name: 'Borrower Report', description: 'All lender accounts with KYC and profile data', category: 'Borrowers' },
  { key: 'rider_report', name: 'Rider Report', description: 'Rider performance and assignment history', category: 'Riders' },
  { key: 'employee_report', name: 'Employee Report', description: 'Employee activity and processed applications', category: 'Employees' },
  { key: 'financial_report', name: 'Financial Report', description: 'Revenue, interest, and penalties breakdown', category: 'Financial' },
  { key: 'revenue_report', name: 'Revenue Report', description: 'Monthly and cumulative revenue analysis', category: 'Financial' },
  { key: 'interest_report', name: 'Interest Report', description: 'Interest earned per loan and period', category: 'Financial' },
  { key: 'penalty_report', name: 'Penalty Report', description: 'Applied penalties with loan and lender details', category: 'Financial' },
  { key: 'overdue_report', name: 'Overdue Loan Report', description: 'All overdue loans with aging analysis', category: 'Loans' },
  { key: 'audit_report', name: 'Audit Report', description: 'System audit trail and user activity', category: 'System' },
  { key: 'ci_report', name: 'Credit Investigation Report', description: 'CI assignments with rider performance', category: 'Operations' },
  { key: 'disbursement_report', name: 'Disbursement Report', description: 'Loan disbursements by method and status', category: 'Disbursements' },
];

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-list';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'get-list':
        // ── [moved from functions/reports-get-list/index.ts] ────────────
        return await handleGetList(req);
      case 'get-history':
        // ── [moved from functions/reports-get-history/index.ts] ─────────
        return await handleGetHistory(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('reports-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/reports-get-list/index.ts] ────────────────────────
async function handleGetList(req: Request) {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    return jsonResponse({ templates: REPORT_TEMPLATES });
  } catch (err) {
    console.error('reports-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
}

// ── [moved from functions/reports-get-history/index.ts] ─────────────────────
async function handleGetHistory(req: Request) {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();
    const url = new URL(req.url);
    const page = parseInt(url.searchParams.get('page') ?? '1');
    const limit = parseInt(url.searchParams.get('limit') ?? '20');
    const templateKey = url.searchParams.get('template_key') ?? url.searchParams.get('type');
    const dateFrom = url.searchParams.get('date_from') ?? url.searchParams.get('start_date');
    const dateTo = url.searchParams.get('date_to') ?? url.searchParams.get('end_date');
    const offset = (page - 1) * limit;

    let query = db
      .from('reports')
      .select(
        `id, report_type, title, parameters, file_path_pdf, file_path_excel,
         generated_by, generated_at, created_at,
         generated_by_user:users!reports_generated_by_fkey(id, first_name, last_name)`,
        { count: 'exact' }
      )
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (templateKey) query = query.eq('report_type', templateKey);
    if (dateFrom) query = query.gte('created_at', dateFrom);
    if (dateTo) query = query.lte('created_at', dateTo);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch report history', 500, 'DB_ERROR');

    const reports = (data ?? []).map((r) => {
      const generatedByUser = embedAsObject(r.generated_by_user);
      return {
        id: r.id,
        template_key: r.report_type,
        template_name: r.title,
        format: r.file_path_pdf ? 'pdf' : r.file_path_excel ? 'xlsx' : 'pdf',
        file_url: r.file_path_pdf ?? r.file_path_excel ?? null,
        generated_by: generatedByUser
          ? `${generatedByUser.first_name} ${generatedByUser.last_name}`.trim()
          : r.generated_by,
        parameters: r.parameters,
        created_at: r.generated_at ?? r.created_at,
      };
    });

    return jsonResponse({
      data: reports,
      meta: {
        page,
        limit,
        total: count ?? 0,
        total_pages: Math.ceil((count ?? 0) / limit),
      },
    });
  } catch (err) {
    console.error('reports-get-history error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
}