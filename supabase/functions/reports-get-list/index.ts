// supabase/functions/reports-get-list/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';

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

serve(async (req) => {
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
});