// supabase/functions/address-geocode/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes actions through `?fn=<action>`:
//
//   address-geocode-backfill → ?fn=backfill  (default)
//       Ini-geocode at ini-save ang lat/lng ng LAHAT ng `addresses` rows na NULL
//       ang coordinates — ito ang nag-aayos sa lumang tasks na
//       "No saved map pin for this task". Ulit-ulitin hanggang `remaining` = 0
//       (ang `?limit=` ang nagtatakda kung ilan kada tawag, default 50, max 200).
//
//   address-geocode-one → ?fn=one&address_id=<uuid>   (o ?fn=one&user_id=<uuid>)
//       Isa lang (o lahat ng address ng isang user) — para sa on-demand na fix
//       ng partikular na lender.
//
// BAKIT: ang pin ng rider maps ay `addresses.latitude/longitude`. Ang mga
// address form (registration / KYC / profile edit / walk-in) ay TEXT lang ang
// isinusulat noon, kaya NULL ang coords at walang pin — kahit may address sa
// file. Ang client-side fallback (`package:geocoding`) ay android/ios lang,
// kaya sa Flutter web talagang walang pin.
//
// AUTH:
//   * Staff JWT (head_manager / employee) — `backfill` at `one`
//   * Rider JWT — `one` lang (kailangan ng pin ng sariling task)
//   * `x-backfill-secret: <GEOCODE_BACKFILL_SECRET>` — one-off maintenance mula
//     sa terminal/CI nang hindi kailangan ng staff account:
//       curl -X POST "$SUPABASE_URL/functions/v1/address-geocode?fn=backfill" \
//         -H "x-backfill-secret: $GEOCODE_BACKFILL_SECRET"
//
// KAILANGAN:
//   supabase secrets set GOOGLE_GEOCODING_API_KEY=AIza...
//   (fallback: GOOGLE_MAPS_API_KEY) + Geocoding API enabled sa Google Cloud.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { isAuthUser, requireAuth } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import {
  backfillMissingCoordinates,
  geocodeAddressesByIds,
  googleGeocodingKey,
} from '../_shared/geocode.ts';

const DEFAULT_ACTION = 'backfill';
const MAX_LIMIT = 200;

/**
 * Constant-time-ish na paghahambing ng shared secret — kapareho ng pattern ng
 * `touch_shared_secret`/webhook auth, at tinatanggihan ang `REPLACE_ME`.
 */
function secretMatches(provided: string | null, expected: string | null): boolean {
  if (!provided || !expected || expected === 'REPLACE_ME') return false;
  if (provided.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < provided.length; i++) {
    diff |= provided.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

function hasBackfillSecret(req: Request): boolean {
  return secretMatches(
    req.headers.get('x-backfill-secret'),
    Deno.env.get('GEOCODE_BACKFILL_SECRET') ?? null,
  );
}

function parseLimit(raw: string | null): number {
  const parsed = Number.parseInt(raw ?? '', 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return 50;
  return Math.min(parsed, MAX_LIMIT);
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const url = new URL(req.url);
    const fn = url.searchParams.get('fn') ?? DEFAULT_ACTION;

    // ── Auth: shared secret (maintenance) O authenticated staff/rider ──────
    if (!hasBackfillSecret(req)) {
      const auth = await requireAuth(req);
      if (!isAuthUser(auth)) return auth;

      const isStaff = auth.role === ROLES.HEAD_MANAGER || auth.role === ROLES.EMPLOYEE;
      if (fn === 'backfill' && !isStaff) {
        return errorResponse(
          `Access denied. Required role: ${ROLES.HEAD_MANAGER} or ${ROLES.EMPLOYEE}`,
          403,
          'FORBIDDEN',
        );
      }
      if (fn === 'one' && !isStaff && auth.role !== ROLES.RIDER) {
        return errorResponse(
          `Access denied. Required role: ${ROLES.HEAD_MANAGER}, ${ROLES.EMPLOYEE} or ${ROLES.RIDER}`,
          403,
          'FORBIDDEN',
        );
      }
    }

    if (googleGeocodingKey() === null) {
      return errorResponse(
        'Geocoding is not configured. Run `supabase secrets set ' +
          'GOOGLE_GEOCODING_API_KEY=AIza...` (o GOOGLE_MAPS_API_KEY) at siguraduhing ' +
          'enabled ang Geocoding API sa Google Cloud project.',
        503,
        'GEOCODE_NOT_CONFIGURED',
      );
    }

    const db = getAdminClient();

    switch (fn) {
      case 'backfill': {
        const limit = parseLimit(url.searchParams.get('limit'));
        const outcome = await backfillMissingCoordinates(db, limit);
        return jsonResponse(
          { ok: true, fn: 'backfill', limit, ...outcome },
          200,
          req,
        );
      }

      case 'one': {
        const addressId = url.searchParams.get('address_id');
        const userId = url.searchParams.get('user_id');

        let ids: string[] = [];
        if (addressId) {
          ids = [addressId];
        } else if (userId) {
          const { data, error } = await db
            .from('addresses')
            .select('id')
            .eq('user_id', userId);
          if (error) {
            return errorResponse(
              `Failed to load addresses: ${error.message}`,
              500,
              'DB_ERROR',
            );
          }
          ids = (data ?? []).map((row) => String(row.id));
        } else {
          return errorResponse(
            'address_id or user_id is required',
            400,
            'VALIDATION_ERROR',
          );
        }

        const outcome = await geocodeAddressesByIds(db, ids, { throttleMs: 0 });
        return jsonResponse(
          { ok: true, fn: 'one', requested: ids.length, ...outcome },
          200,
          req,
        );
      }

      default:
        return errorResponse(
          `Unknown action: ${fn}. Use ?fn=backfill or ?fn=one.`,
          400,
          'VALIDATION_ERROR',
        );
    }
  } catch (e) {
    console.error('[address-geocode] failed:', e);
    return errorResponse(
      e instanceof Error ? e.message : 'Unexpected error',
      500,
      'SERVER_ERROR',
      undefined,
      req,
    );
  }
});
