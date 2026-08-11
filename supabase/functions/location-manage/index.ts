// supabase/functions/location-manage/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   location-update-rider  →  ?fn=update-rider
//   location-get-rider     →  ?fn=get-rider
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { checkRateLimit } from '../_shared/rate_limiter.ts';

// ── [moved from location-update-rider] ──────────────────────────────────────
const MAX_COORD_JUMP_KM = 50;

// ── [moved from location-update-rider] ──────────────────────────────────────
function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'update-rider';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'update-rider':
        // ── [moved from functions/location-update-rider/index.ts] ───────
        return await handleUpdateRider(req);
      case 'get-rider':
        // ── [moved from functions/location-get-rider/index.ts] ──────────
        return await handleGetRider(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('location-manage error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/location-update-rider/index.ts] ───────────────────
async function handleUpdateRider(req: Request) {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.RIDER);
    if (roleCheck) return roleCheck;

    const rateLimitKey = `location_update_${authResult.id}`;
    const limited = await checkRateLimit({ key: rateLimitKey, maxAttempts: 2, windowMinutes: 60 });
    if (limited.allowed === false) return errorResponse('Rate limit exceeded. One update per 30s.', 429, 'RATE_LIMIT');

    const body = await req.json();
    const { latitude, longitude, accuracy } = body;

    if (
      typeof latitude !== 'number' ||
      typeof longitude !== 'number' ||
      latitude < -90 || latitude > 90 ||
      longitude < -180 || longitude > 180
    ) {
      return errorResponse('Invalid GPS coordinates', 400, 'INVALID_COORDINATES');
    }

    const db = getAdminClient();

    const { data: existing } = await db
      .from('rider_locations')
      .select('latitude, longitude, updated_at')
      .eq('rider_id', authResult.id)
      .single();

    if (existing) {
      const distKm = haversineKm(
        Number(existing.latitude), Number(existing.longitude),
        latitude, longitude
      );
      const secondsSinceLast = (Date.now() - new Date(existing.updated_at).getTime()) / 1000;
      if (secondsSinceLast < 60 && distKm > MAX_COORD_JUMP_KM) {
        console.warn(`GPS spoof detected for rider ${authResult.id}: ${distKm.toFixed(2)}km in ${secondsSinceLast.toFixed(0)}s`);
        return errorResponse('GPS coordinates rejected: impossible movement detected', 422, 'GPS_SPOOF_DETECTED');
      }
    }

    const { error } = await db.from('rider_locations').upsert(
      {
        rider_id: authResult.id,
        latitude,
        longitude,
        accuracy: accuracy ?? null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'rider_id' }
    );

    if (error) return errorResponse('Failed to update location', 500, 'DB_ERROR');

    return jsonResponse({ success: true, latitude, longitude });
  } catch (err) {
    console.error('location-update-rider error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
}

// ── [moved from functions/location-get-rider/index.ts] ──────────────────────
async function handleGetRider(req: Request) {
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
      const { data: loanRows } = await db
        .from('loans')
        .select('id')
        .eq('lender_id', authResult.id);
      const loanIds = (loanRows ?? []).map((r) => r.id);
      const { data: scheduleRows } = await db
        .from('loan_schedules')
        .select('id')
        .in('loan_id', loanIds);
      const scheduleIds = (scheduleRows ?? []).map((r) => r.id);

      const { data: assignment } = await db
        .from('collection_assignments')
        .select('id, status, rider_id')
        .eq('rider_id', riderId)
        .eq('status', 'accepted')
        .in('loan_schedule_id', scheduleIds)
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
}