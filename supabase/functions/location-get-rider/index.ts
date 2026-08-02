// supabase/functions/location-get-rider/index.ts
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

    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE, ROLES.LENDER);
    if (roleCheck) return roleCheck;

    const url = new URL(req.url);
    const riderId = url.searchParams.get('rider_id');
    if (!riderId) return errorResponse('rider_id is required', 400, 'MISSING_PARAM');

    const db = getAdminClient();

    if (authResult.role === ROLES.LENDER) {
      const { data: assignment } = await db
        .from('collection_assignments')
        .select('id, status, rider_id')
        .eq('rider_id', riderId)
        .eq('status', 'accepted')
        .in(
          'loan_schedule_id',
          db
            .from('loan_schedules')
            .select('id')
            .in(
              'loan_id',
              db.from('loans').select('id').eq('lender_id', authResult.id)
            )
        )
        .limit(1)
        .single();

      if (!assignment) {
        return errorResponse(
          'Access denied: No active collection assignment links this rider to your loan',
          403,
          'FORBIDDEN'
        );
      }
    }

    const { data, error } = await db
      .from('rider_locations')
      .select('rider_id, latitude, longitude, accuracy, updated_at')
      .eq('rider_id', riderId)
      .single();

    if (error || !data) return errorResponse('Rider location not found', 404, 'NOT_FOUND');

    const staleSecs = (Date.now() - new Date(data.updated_at).getTime()) / 1000;
    return jsonResponse({
      rider_id: data.rider_id,
      latitude: data.latitude,
      longitude: data.longitude,
      accuracy: data.accuracy,
      updated_at: data.updated_at,
      is_stale: staleSecs > 120,
    });
  } catch (err) {
    console.error('location-get-rider error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});