// supabase/functions/kpi-rider/index.ts
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
    const roleCheck = requireRole(authResult, ROLES.RIDER);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();
    const riderId = authResult.id;

    const [
      { count: totalAssigned },
      { count: totalCompleted },
      { count: totalFailed },
      { count: totalCiAssigned },
      { count: totalCiCompleted },
    ] = await Promise.all([
      db.from('collection_assignments').select('*', { count: 'exact', head: true })
        .eq('rider_id', riderId),
      db.from('collection_assignments').select('*', { count: 'exact', head: true })
        .eq('rider_id', riderId).eq('status', 'completed'),
      db.from('collection_assignments').select('*', { count: 'exact', head: true })
        .eq('rider_id', riderId).eq('status', 'failed'),
      db.from('credit_investigations').select('*', { count: 'exact', head: true })
        .eq('rider_id', riderId),
      db.from('credit_investigations').select('*', { count: 'exact', head: true })
        .eq('rider_id', riderId).eq('status', 'completed'),
    ]);

    const { data: paymentData } = await db
      .from('payments')
      .select('amount')
      .eq('recorded_by', riderId)
      .eq('status', 'verified');

    const totalCollected = (paymentData ?? []).reduce(
      (sum: number, p: any) => sum + Number(p.amount), 0
    );

    return jsonResponse({
      total_assigned_collections: totalAssigned ?? 0,
      total_completed_collections: totalCompleted ?? 0,
      total_failed_collections: totalFailed ?? 0,
      total_amount_collected: totalCollected,
      total_ci_assignments: totalCiAssigned ?? 0,
      total_ci_completed: totalCiCompleted ?? 0,
    });
  } catch (err) {
    console.error('kpi-rider error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});