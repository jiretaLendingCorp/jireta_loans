// supabase/functions/location-update-rider/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { checkRateLimit } from '../_shared/rate_limiter.ts';

const MAX_COORD_JUMP_KM = 50;

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

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.RIDER);
    if (roleCheck) return roleCheck;

    const rateLimitKey = `location_update_${authResult.id}`;
    const limited = await checkRateLimit(rateLimitKey, 2, 60);
    if (limited) return errorResponse('Rate limit exceeded. One update per 30s.', 429, 'RATE_LIMIT');

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
});