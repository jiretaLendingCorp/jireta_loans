// supabase/functions/location-manage/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   location-update-rider  →  ?fn=update-rider
//   location-get-rider     →  ?fn=get-rider
//   location-list-tracked  →  ?fn=list-tracked
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
import { embedAsObject } from '../_shared/types.ts';

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
      case 'list-tracked':
        // ── Live lender tracking: all riders with an ACCEPTED (or in-flight)
        //    assignment on the lender's loans across collection / CI / delivery.
        return await handleListTracked(req);
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
    if (!isAuthUser(authResult)) {
      const body = await authResult.clone().text();
      console.warn('update-rider auth failed:', authResult.status, body);
      return authResult;
    }
    const roleCheck = requireRole(authResult, ROLES.RIDER);
    if (roleCheck) {
      const body = await roleCheck.clone().text();
      console.warn('update-rider role check failed:', roleCheck.status, body);
      return roleCheck;
    }

    const rateLimitKey = `location_update_${authResult.id}`;
    const limited = await checkRateLimit({ key: rateLimitKey, maxAttempts: 120, windowMinutes: 60 });
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

    let assignmentType: string | null = null;
    let assignmentStatus: string | null = null;

    if (authResult.role === ROLES.LENDER) {
      // Mirror `list-tracked`: the rider's live location is only exposed to the
      // lender while there is an ACTIVE assignment (accepted/in_progress
      // collection or CI, or an in-flight rider-delivery disbursement) on one
      // of the lender's loans.
      const [collectionRows, ciRows, disbRows] = await Promise.all([
        (db
          .from('collection_assignments')
          .select('id, status, updated_at, loan_schedule:loan_schedules(loan:loans(lender_id))')
          .eq('rider_id', riderId)
          .in('status', TRACKED_COLLECTION_STATUSES)
          .eq('loan_schedule.loan.lender_id', authResult.id)) as unknown as Promise<{
          data: TrackedRow[] | null;
          error: { message?: string } | null;
        }>,
        (db
          .from('credit_investigations')
          .select('id, status, updated_at, loan:loans(lender_id)')
          .eq('rider_id', riderId)
          .in('status', TRACKED_CI_STATUSES)
          .eq('loan.lender_id', authResult.id)) as unknown as Promise<{
          data: TrackedRow[] | null;
          error: { message?: string } | null;
        }>,
        (db
          .from('disbursements')
          .select('id, status, updated_at, loan:loans(lender_id)')
          .eq('rider_id', riderId)
          .eq('method', 'rider_delivery')
          .eq('status', 'pending')
          .eq('loan.lender_id', authResult.id)) as unknown as Promise<{
          data: TrackedRow[] | null;
          error: { message?: string } | null;
        }>,
      ]);

      const collectionCount = collectionRows.data?.length ?? 0;
      const ciCount = ciRows.data?.length ?? 0;
      const disbCount = disbRows.data?.length ?? 0;

      // A query error yields `data: null`, which would otherwise masquerade as
      // a legitimately-empty result and produce a false "access denied" with
      // all-zero counts. Surface it instead of guessing.
      const queryErrors = [collectionRows.error, ciRows.error, disbRows.error].filter(Boolean);
      if (queryErrors.length > 0) {
        console.error(
          `get-rider lookup failed for rider ${riderId} by lender ${authResult.id}:`,
          queryErrors.map((e) => e?.message).join(' | ')
        );
        return errorResponse('Failed to verify assignment access', 500, 'DB_ERROR');
      }

      if (collectionCount === 0 && ciCount === 0 && disbCount === 0) {
        console.warn(
          `get-rider access denied for rider ${riderId} by lender ${authResult.id}: collection=${collectionCount}, ci=${ciCount}, disbursement=${disbCount}`
        );
        return errorResponse(
          `Access denied: No active assignment links this rider (${riderId}) to your account (collection=${collectionCount}, ci=${ciCount}, disbursement=${disbCount})`,
          403,
          'FORBIDDEN'
        );
      }

      // The rider may hold several active assignments at once (e.g. an old
      // accepted collection plus a CI they just started). Prefer the CI so the
      // tracking label matches the loan stage the rider is actually on; within
      // the same type, an in_progress task beats an accepted one, and the most
      // recently updated wins as a final tiebreaker.
      const candidates: Array<{ type: 'collection' | 'ci' | 'disbursement'; row: TrackedRow }> = [
        ...(collectionRows.data ?? []).map((row) => ({ type: 'collection' as const, row })),
        ...(ciRows.data ?? []).map((row) => ({ type: 'ci' as const, row })),
        ...(disbRows.data ?? []).map((row) => ({ type: 'disbursement' as const, row })),
      ];
      const TYPE_PRIORITY: Record<string, number> = { ci: 0, collection: 1, disbursement: 2 };
      candidates.sort((a, b) => {
        const aType = TYPE_PRIORITY[a.type] ?? 3;
        const bType = TYPE_PRIORITY[b.type] ?? 3;
        if (aType !== bType) return aType - bType;
        const aActive = a.row.status === 'in_progress' ? 1 : 0;
        const bActive = b.row.status === 'in_progress' ? 1 : 0;
        if (aActive !== bActive) return bActive - aActive;
        const aUpdated = a.row.updated_at ? new Date(a.row.updated_at).getTime() : 0;
        const bUpdated = b.row.updated_at ? new Date(b.row.updated_at).getTime() : 0;
        return bUpdated - aUpdated;
      });
      const chosen = candidates[0];
      if (chosen) {
        assignmentType = chosen.type;
        assignmentStatus = chosen.row.status ?? null;
      }
    }

    // For the lender, also return their own primary address (the destination
    // the rider is navigating to) so the tracking screen can draw the road
    // route from the rider's live position, matching the rider's navigate UI.
    let destinationLatitude: number | null = null;
    let destinationLongitude: number | null = null;
    let destinationAddress: string | null = null;
    let destinationLabel: string | null = null;
    if (authResult.role === ROLES.LENDER) {
      const { data: lenderUser } = await db
        .from('users')
        .select(
          'first_name, last_name, addresses:addresses(address_type, street, barangay, city, province, zip_code, latitude, longitude, is_primary)'
        )
        .eq('id', authResult.id)
        .single();

      const addresses = Array.isArray(lenderUser?.addresses)
        ? (lenderUser!.addresses as TrackedRow[])
        : [];
      const withCoords = addresses.find(
        (a) => a.latitude != null && a.longitude != null
      );
      const dest = withCoords ?? addresses.find((a) => a.is_primary) ?? addresses[0];
      if (dest) {
        if (dest.latitude != null && dest.longitude != null) {
          destinationLatitude = Number(dest.latitude);
          destinationLongitude = Number(dest.longitude);
        }
        const parts = [dest.street, dest.barangay, dest.city, dest.province]
          .filter((p) => p != null && String(p).trim() !== '');
        if (parts.length > 0) destinationAddress = parts.join(', ');
        const labelParts = [dest.street, dest.barangay, dest.city]
          .filter((p) => p != null && String(p).trim() !== '');
        if (labelParts.length > 0) destinationLabel = labelParts.join(', ');
      }
    }

    const { data, error } = await db
      .from('rider_locations')
      .select('rider_id, latitude, longitude, accuracy, updated_at')
      .eq('rider_id', riderId)
      .single();

    if (error || !data) {
      // For the lender, still return the destination so the tracking map can
      // show where the rider is heading even before the first GPS fix. Other
      // roles keep the 404 (no fix yet).
      if (authResult.role === ROLES.LENDER) {
        return jsonResponse({
          rider_id: riderId,
          latitude: null,
          longitude: null,
          accuracy: null,
          updated_at: null,
          is_stale: true,
          assignment_type: assignmentType,
          assignment_status: assignmentStatus,
          destination_latitude: destinationLatitude,
          destination_longitude: destinationLongitude,
          destination_address: destinationAddress,
          destination_label: destinationLabel,
        });
      }
      return errorResponse('Rider location not found', 404, 'NOT_FOUND');
    }

    const staleSecs = (Date.now() - new Date(data.updated_at).getTime()) / 1000;
    return jsonResponse({
      rider_id: data.rider_id,
      latitude: data.latitude,
      longitude: data.longitude,
      accuracy: data.accuracy,
      updated_at: data.updated_at,
      is_stale: staleSecs > 120,
      assignment_type: assignmentType,
      assignment_status: assignmentStatus,
      destination_latitude: destinationLatitude,
      destination_longitude: destinationLongitude,
      destination_address: destinationAddress,
      destination_label: destinationLabel,
    });
  } catch (err) {
    console.error('location-get-rider error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
}

// ── Live lender tracking: riders currently visible to the lender ────────────
//
// Business rule: a rider's live location is only exposed to the lender AFTER
// the rider accepts the assignment. This action returns one entry per ACTIVE
// assignment (accepted/in_progress collection or CI, or an in-flight
// rider-delivery disbursement) on any of the lender's loans, each merged with
// the rider's latest GPS fix from `rider_locations` (when one exists).
// `assignment_type` ∈ collection | ci | disbursement.
const TRACKED_COLLECTION_STATUSES = ['accepted', 'in_progress'];
const TRACKED_CI_STATUSES = ['accepted', 'in_progress'];

// Deeply-nested renamed embeds in the select strings below trip supabase-js's
// type-level PostgREST parser (ParserError) — see collections-view/index.ts.
// Rows are therefore re-typed here; runtime behavior is unchanged.
type TrackedRow = Record<string, any>;

async function handleListTracked(req: Request) {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.LENDER);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();

    const riderSelect = 'rider:rider_profiles(id, users!rider_profiles_id_fkey(first_name, last_name))';

    // ── Step 1: pull every ACTIVE assignment on the lender's loans ──────────
    const [collectionRows, ciRows, disbRows] = await Promise.all([
      (db
        .from('collection_assignments')
        .select(
          `id, status, rider_id, created_at,
           loan_schedule:loan_schedules(loan:loans(id, loan_number, lender_id)),
           ${riderSelect}`
        )
        .in('status', TRACKED_COLLECTION_STATUSES)
        .eq('loan_schedule.loan.lender_id', authResult.id)) as unknown as Promise<{
        data: TrackedRow[] | null;
        error: { message?: string } | null;
      }>,
      (db
        .from('credit_investigations')
        .select(
          `id, status, rider_id, created_at,
           loan:loans(id, loan_number, lender_id),
           ${riderSelect}`
        )
        .in('status', TRACKED_CI_STATUSES)
        .eq('loan.lender_id', authResult.id)) as unknown as Promise<{
        data: TrackedRow[] | null;
        error: { message?: string } | null;
      }>,
      (db
        .from('disbursements')
        .select(
          `id, status, rider_id, created_at,
           loan:loans(id, loan_number, lender_id),
           ${riderSelect}`
        )
        .eq('method', 'rider_delivery')
        .eq('status', 'pending')
        .eq('loan.lender_id', authResult.id)) as unknown as Promise<{
        data: TrackedRow[] | null;
        error: { message?: string } | null;
      }>,
    ]);

    const assignments: Array<{
      type: 'collection' | 'ci' | 'disbursement';
      assignmentId: string;
      status: string;
      riderId: string;
      riderName: string | null;
      loanId: string;
      loanNumber: string;
    }> = [];

    for (const row of (collectionRows.data ?? [])) {
      const loan = embedAsObject(row.loan_schedule?.loan);
      const rider = embedAsObject(row.rider);
      const riderUser = rider ? embedAsObject(rider.users) : null;
      if (!loan || !rider) continue;
      assignments.push({
        type: 'collection',
        assignmentId: row.id,
        status: row.status,
        riderId: rider.id,
        riderName: [riderUser?.first_name, riderUser?.last_name].filter(Boolean).join(' ') || null,
        loanId: loan.id,
        loanNumber: loan.loan_number,
      });
    }

    for (const row of (ciRows.data ?? [])) {
      const loan = embedAsObject(row.loan);
      const rider = embedAsObject(row.rider);
      const riderUser = rider ? embedAsObject(rider.users) : null;
      if (!loan || !rider) continue;
      assignments.push({
        type: 'ci',
        assignmentId: row.id,
        status: row.status,
        riderId: rider.id,
        riderName: [riderUser?.first_name, riderUser?.last_name].filter(Boolean).join(' ') || null,
        loanId: loan.id,
        loanNumber: loan.loan_number,
      });
    }

    for (const row of (disbRows.data ?? [])) {
      const loan = embedAsObject(row.loan);
      const rider = embedAsObject(row.rider);
      const riderUser = rider ? embedAsObject(rider.users) : null;
      if (!loan || !rider) continue;
      assignments.push({
        type: 'disbursement',
        assignmentId: row.id,
        status: row.status,
        riderId: rider.id,
        riderName: [riderUser?.first_name, riderUser?.last_name].filter(Boolean).join(' ') || null,
        loanId: loan.id,
        loanNumber: loan.loan_number,
      });
    }

    if (assignments.length === 0) {
      return jsonResponse({ riders: [], total: 0 });
    }

    // ── Step 2: batch-load the latest GPS fix for every tracked rider ───────
    const riderIds = Array.from(new Set(assignments.map((a) => a.riderId)));
    const { data: locRows, error: locErr } = await db
      .from('rider_locations')
      .select('rider_id, latitude, longitude, accuracy, updated_at')
      .in('rider_id', riderIds);

    if (locErr) {
      return errorResponse('Failed to load rider locations', 500, 'DB_ERROR');
    }

    const locations = new Map<string, {
      latitude: number;
      longitude: number;
      accuracy: number | null;
      updated_at: string;
    }>();
    for (const row of (locRows ?? [])) {
      locations.set(row.rider_id as string, {
        latitude: Number(row.latitude),
        longitude: Number(row.longitude),
        accuracy: row.accuracy != null ? Number(row.accuracy) : null,
        updated_at: row.updated_at as string,
      });
    }

    // ── Step 3: merge assignments with locations and return ────────────────
    const now = Date.now();
    const riders = assignments.map((a) => {
      const loc = locations.get(a.riderId);
      let updatedAt: string | null = null;
      let isStale = true;
      if (loc) {
        updatedAt = loc.updated_at;
        isStale = (now - new Date(loc.updated_at).getTime()) / 1000 > 120;
      }
      return {
        rider_id: a.riderId,
        rider_name: a.riderName,
        assignment_type: a.type,
        assignment_id: a.assignmentId,
        assignment_status: a.status,
        loan_id: a.loanId,
        loan_number: a.loanNumber,
        latitude: loc?.latitude ?? null,
        longitude: loc?.longitude ?? null,
        accuracy: loc?.accuracy ?? null,
        location_updated_at: updatedAt,
        is_stale: isStale,
      };
    });

    return jsonResponse({ riders, total: riders.length });
  } catch (err) {
    console.error('location-list-tracked error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
}
