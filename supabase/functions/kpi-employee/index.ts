// supabase/functions/kpi-employee/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();
    const empId = authResult.id;

    const [
      { count: totalLenders },
      { count: totalApplications },
      { count: totalApproved },
      { count: totalRejected },
      { count: totalActive },
      { count: totalCompleted },
      { count: totalCollections },
    ] = await Promise.all([
      db.from('users').select('*', { count: 'exact', head: true })
        .eq('created_by', empId).eq('roles.name', 'lender'),
      db.from('loans').select('*', { count: 'exact', head: true })
        .eq('processed_by', empId),
      db.from('loans').select('*', { count: 'exact', head: true })
        .eq('processed_by', empId).in('status', ['approved', 'active', 'completed']),
      db.from('loans').select('*', { count: 'exact', head: true })
        .eq('processed_by', empId).eq('status', 'rejected'),
      db.from('loans').select('*', { count: 'exact', head: true })
        .eq('processed_by', empId).eq('status', 'active'),
      db.from('loans').select('*', { count: 'exact', head: true })
        .eq('processed_by', empId).eq('status', 'completed'),
      db.from('collection_assignments').select('*', { count: 'exact', head: true })
        .eq('assigned_by', empId),
    ]);

    return jsonResponse({
      total_lenders_managed: totalLenders ?? 0,
      total_applications_processed: totalApplications ?? 0,
      total_approved_loans: totalApproved ?? 0,
      total_rejected_loans: totalRejected ?? 0,
      total_active_loans: totalActive ?? 0,
      total_completed_loans: totalCompleted ?? 0,
      total_collections_managed: totalCollections ?? 0,
    });
  } catch (err) {
    console.error('kpi-employee error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});