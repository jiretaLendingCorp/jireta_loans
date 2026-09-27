// supabase/functions/_shared/geocode.ts
// ─────────────────────────────────────────────────────────────────────────────
// Server-side geocoding ng `addresses` rows na TEXT-ONLY ang na-save.
//
// BAKIT KAILANGAN:
// Ang pin ng rider maps (Live Tracking / Navigate to Lender / CI) ay galing sa
// `addresses.latitude` at `addresses.longitude` — parehong kailangang non-null
// (tingnan ang `destinationFromAddresses()` sa
// lib/presentation/shared/widgets/map/map_anim_utils.dart). Pero ang mga address
// form (registration, KYC, profile edit, walk-in wizard) ay street/barangay/
// city/province TEXT lang ang isinusulat, kaya NULL ang coordinates at walang
// pin — "No saved map pin for this task" kahit may address sa file.
//
// Ang client-side fallback (`package:geocoding`) ay android/ios lang ang
// implementation, kaya sa Flutter web hindi ito gumagana; sa mobile naman
// paulit-ulit itong nag-geocode at hindi nase-save.
//
// SOLUSYON: i-geocode ONCE sa server (Google Geocoding API, country:PH) at
// i-persist ang lat/lng pabalik sa `addresses` — isang beses lang, at lahat ng
// client (web + mobile) at lahat ng screens ay may naka-save nang pin.
//
// SECRET (server-only, hindi lumalabas sa browser):
//   supabase secrets set GOOGLE_GEOCODING_API_KEY=AIza...
// Fallback: GOOGLE_MAPS_API_KEY kung iyon na ang naka-set sa project secrets.
// Ang Geocoding API ay kailangang enabled sa parehong Google Cloud project.
// ─────────────────────────────────────────────────────────────────────────────
import { getAdminClient } from './db.ts';

const GEOCODE_ENDPOINT = 'https://maps.googleapis.com/maps/api/geocode/json';

/** Mga placeholder na hindi tunay na key (hal. `.env.example`). */
const PLACEHOLDER_KEYS = new Set([
  'YOUR_GOOGLE_MAPS_API_KEY',
  'your-google-maps-key',
  'REPLACE_ME',
]);

export interface AddressParts {
  street?: string | null;
  barangay?: string | null;
  city?: string | null;
  province?: string | null;
  zip_code?: string | null;
  region?: string | null;
}

export interface AddressRowForGeocode extends AddressParts {
  id: string;
  latitude?: number | null;
  longitude?: number | null;
  created_at?: string | null;
}

export interface GeocodeResult {
  latitude: number;
  longitude: number;
  formattedAddress: string;
  locationType: string;
  partialMatch: boolean;
}

export interface GeocodeOutcome {
  scanned: number;
  geocoded: number;
  failed: number;
  skipped: number;
}

interface GeocodeEntry {
  formatted_address?: string;
  partial_match?: boolean;
  geometry?: {
    location?: { lat?: number; lng?: number };
    location_type?: string;
  };
}

export interface GeocodeApiResponse {
  status?: string;
  error_message?: string;
  results?: GeocodeEntry[];
}

/** Server-side key para sa Geocoding API (null kapag wala pa o placeholder). */
export function googleGeocodingKey(): string | null {
  const raw = Deno.env.get('GOOGLE_GEOCODING_API_KEY') ??
    Deno.env.get('GOOGLE_MAPS_API_KEY') ??
    '';
  const key = raw.trim();
  if (!key || PLACEHOLDER_KEYS.has(key)) return null;
  return key;
}

/**
 * Isang query string mula sa structured address:
 * "street, barangay, city, province, zip_code, Philippines".
 *
 * Kailangan ng hindi bababa sa DALAWANG bahagi: ang street-only na query (hal.
 * "Purok 1") ay nagbibigay ng malayong centroid, at mas mabuting walang pin kaysa
 * maling pin. Ang `zip_code` ay kasama dahil malaking tulong ito sa Google sa
 * Pilipinas.
 */
export function buildAddressQuery(parts: AddressParts): string | null {
  const ordered = [
    parts.street,
    parts.barangay,
    parts.city,
    parts.province,
    parts.zip_code,
  ]
    .map((p) => (typeof p === 'string' ? p.trim() : ''))
    .filter((p) => p !== '');

  if (ordered.length < 2) return null;

  // Dedupe: ang ibang lumang record ay paulit-ulit ang city/province sa street.
  const seen = new Set<string>();
  const unique: string[] = [];
  for (const part of ordered) {
    const key = part.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(part);
  }

  return `${unique.join(', ')}, Philippines`;
}

/** Isang result → `GeocodeResult` (null kapag kulang/walang saysay ang coords). */
export function toGeocodeResult(entry: GeocodeEntry | null | undefined): GeocodeResult | null {
  const lat = entry?.geometry?.location?.lat;
  const lng = entry?.geometry?.location?.lng;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  // Kapareho ng CHECK constraints ng `addresses` table + tanggihan ang
  // Null Island (0,0) — iyon ang "walang data" na sagot ng Google.
  if (lat <= -90 || lat >= 90 || lng <= -180 || lng >= 180) return null;
  if (lat === 0 && lng === 0) return null;
  return {
    latitude: lat,
    longitude: lng,
    formattedAddress: entry?.formatted_address ?? '',
    locationType: entry?.geometry?.location_type ?? 'UNKNOWN',
    partialMatch: entry?.partial_match === true,
  };
}

/**
 * Pinakatumpak na result: mas gusto ang street-level (ROOFTOP o
 * RANGE_INTERPOLATED) at hindi `partial_match`; kapag wala, ang unang
 * kandidato na lang (GEOMETRIC_CENTER/APPROXIMATE) — sapat na para sa pin.
 */
export function pickBestResult(results: GeocodeEntry[] | undefined): GeocodeResult | null {
  const candidates = (results ?? [])
    .map(toGeocodeResult)
    .filter((r): r is GeocodeResult => r !== null);
  if (candidates.length === 0) return null;

  const exact = candidates.filter((c) => !c.partialMatch);
  const pool = exact.length > 0 ? exact : candidates;
  const streetLevel = pool.find(
    (c) => c.locationType === 'ROOFTOP' || c.locationType === 'RANGE_INTERPOLATED',
  );
  return streetLevel ?? pool[0];
}

/** Pure parsing (testable): status + pinaka-tumpak na result. */
export function parseGeocodeResponse(json: GeocodeApiResponse | null | undefined): {
  result: GeocodeResult | null;
  status: string;
  error?: string;
} {
  const status = json?.status ?? 'UNKNOWN_STATUS';
  if (status !== 'OK') {
    return { result: null, status, error: json?.error_message };
  }
  return { result: pickBestResult(json?.results), status };
}

// ── Per-invocation cache: isang isolate na nagba-backfill ay hindi na
//    nag-geocode ng magkaparehong address nang dalawang beses. ──────────────
const memoryCache = new Map<string, GeocodeResult | null>();

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchWithTimeout(url: string, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

/** Google Geocoding API call. `null` kapag walang nahanap o may error. */
export async function geocodeAddressParts(
  parts: AddressParts,
  key: string,
): Promise<GeocodeResult | null> {
  const query = buildAddressQuery(parts);
  if (!query) return null;

  const cached = memoryCache.get(query);
  if (cached !== undefined) return cached;

  const url = `${GEOCODE_ENDPOINT}?address=${encodeURIComponent(query)}` +
    `&components=${encodeURIComponent('country:PH')}` +
    `&region=ph&language=en&key=${encodeURIComponent(key)}`;

  let result: GeocodeResult | null = null;
  try {
    const res = await fetchWithTimeout(url, 9000);
    if (!res.ok) {
      console.error('[geocode] HTTP', res.status, 'for', query);
    } else {
      const json = (await res.json()) as GeocodeApiResponse;
      const parsed = parseGeocodeResponse(json);
      if (parsed.status !== 'OK' && parsed.status !== 'ZERO_RESULTS') {
        console.error('[geocode] Google status', parsed.status, parsed.error ?? '', query);
      }
      result = parsed.result;
    }
  } catch (e) {
    console.error('[geocode] request failed:', e);
  }

  memoryCache.set(query, result);
  return result;
}

/**
 * Geocode + persist para sa isang row.
 *
 * `overwrite: false` (default) = idempotent: hindi ginagalaw ang row na may
 * coords na. `overwrite: true` = inaayos muli ang pin pagkatapos na-EDIT ang
 * address text (kung hindi, stale ang pin sa lumang address).
 */
export async function geocodeAndPersistRow(
  db: ReturnType<typeof getAdminClient>,
  row: AddressRowForGeocode,
  key: string,
  overwrite = false,
): Promise<boolean> {
  if (!overwrite && row.latitude != null && row.longitude != null) return false;

  const result = await geocodeAddressParts(row, key);
  if (!result) return false;

  let update = db
    .from('addresses')
    .update({ latitude: result.latitude, longitude: result.longitude })
    .eq('id', row.id);
  if (!overwrite) {
    // Huwag sakupin ang row na may coords na (race sa ibang geocode).
    update = update.is('latitude', null);
  }
  const { error } = await update;

  if (error) {
    console.error('[geocode] update failed:', row.id, error.message);
    return false;
  }
  console.log('[geocode] saved pin', row.id, result.latitude, result.longitude, result.locationType);
  return true;
}

/**
 * Geocode ang mga address row na binigay (sa pamamagitan ng id). Sunod-sunod
 * (hindi parallel) para hindi lumampas sa QPS ng Geocoding API.
 */
export async function geocodeAddressesByIds(
  db: ReturnType<typeof getAdminClient>,
  ids: Array<string | null | undefined>,
  opts: { throttleMs?: number; overwrite?: boolean } = {},
): Promise<GeocodeOutcome> {
  const outcome: GeocodeOutcome = { scanned: 0, geocoded: 0, failed: 0, skipped: 0 };
  const unique = [...new Set(
    ids.filter((id): id is string => typeof id === 'string' && id.trim() !== ''),
  )];
  if (unique.length === 0) return outcome;

  const key = googleGeocodingKey();
  if (!key) {
    console.error(
      '[geocode] GOOGLE_GEOCODING_API_KEY is not set — walang pin na mase-save. ' +
        'Itakda: supabase secrets set GOOGLE_GEOCODING_API_KEY=AIza...',
    );
    outcome.skipped = unique.length;
    return outcome;
  }

  const throttleMs = opts.throttleMs ?? 120;
  for (const id of unique) {
    const { data: row, error } = await db
      .from('addresses')
      .select('id, street, barangay, city, province, zip_code, latitude, longitude')
      .eq('id', id)
      .maybeSingle();

    if (error || !row) {
      console.error('[geocode] row lookup failed:', id, error?.message ?? 'not found');
      outcome.skipped++;
      continue;
    }

    outcome.scanned++;
    const overwrite = opts.overwrite === true;
    const withCoords = row.latitude != null && row.longitude != null;
    const saved = !overwrite && withCoords
      ? false
      : await geocodeAndPersistRow(db, row as AddressRowForGeocode, key, overwrite);

    if (!overwrite && withCoords) outcome.skipped++;
    else if (saved) outcome.geocoded++;
    else outcome.failed++;

    if (throttleMs > 0) await sleep(throttleMs);
  }
  return outcome;
}

export interface BackfillOutcome extends GeocodeOutcome {
  remaining: number;
}

/**
 * One-off maintenance: geocode LAHAT ng `addresses` rows na NULL ang lat/lng
 * (ito ang nag-aayos ng lumang tasks na walang pin). Ang `limit` ay para
 * hindi lumampas ang isang invocation sa wall-clock/API quota — ulit-ulitin
 * ang tawag hanggang `remaining` = 0.
 */
export async function backfillMissingCoordinates(
  db: ReturnType<typeof getAdminClient>,
  limit = 50,
): Promise<BackfillOutcome> {
  const outcome: BackfillOutcome = {
    scanned: 0,
    geocoded: 0,
    failed: 0,
    skipped: 0,
    remaining: 0,
  };

  const key = googleGeocodingKey();
  if (!key) return outcome;

  const { data: rows, error } = await db
    .from('addresses')
    .select('id, street, barangay, city, province, zip_code, latitude, longitude')
    .or('latitude.is.null,longitude.is.null')
    .order('created_at', { ascending: true })
    .limit(Math.max(1, Math.min(limit, 200)));

  if (error) {
    console.error('[geocode] backfill select failed:', error.message);
    throw error;
  }

  for (const row of rows ?? []) {
    outcome.scanned++;
    const saved = await geocodeAndPersistRow(db, row as AddressRowForGeocode, key);
    if (saved) outcome.geocoded++;
    else outcome.failed++;
    await sleep(120);
  }

  const { count } = await db
    .from('addresses')
    .select('id', { count: 'exact', head: true })
    .or('latitude.is.null,longitude.is.null');
  outcome.remaining = count ?? 0;
  return outcome;
}

/**
 * Fire-and-forget geocoding mula sa write paths (registration, KYC, profile
 * edit, walk-in). Hindi hinihintay ang Google API para hindi bumagal ang
 * response ng function: `EdgeRuntime.waitUntil` ang nagpapanatili sa isolate
 * hanggang matapos ito.
 */
export function geocodeInBackground(
  db: ReturnType<typeof getAdminClient>,
  addressIds: Array<string | null | undefined>,
  opts: { overwrite?: boolean } = {},
): void {
  const ids = [...new Set(
    addressIds.filter((id): id is string => typeof id === 'string' && id.trim() !== ''),
  )];
  if (ids.length === 0) return;

  const task = geocodeAddressesByIds(db, ids, { overwrite: opts.overwrite }).catch((e) =>
    console.error('[geocode] background task failed:', e)
  );

  const runtime = (globalThis as {
    EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void };
  }).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(task);
    return;
  }
  // Walang waitUntil hook (`deno run` / lumang runtime) — huwag pa ring i-await.
  void task;
}
