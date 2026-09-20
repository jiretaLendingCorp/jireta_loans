// supabase/functions/_shared/cors.ts
//
// HARDENED: Added 'accept' to Access-Control-Allow-Headers.
// ADDED: successResponse helper used by in-office-submit and similar functions.
// SECURITY: Access-Control-Allow-Origin is restricted to the configured app
// origin. In dev (CORS_ALLOWED_ORIGINS unset) `*` is kept so local Flutter
// web/testing keeps working; in production set CORS_ALLOWED_ORIGINS to the real
// web origin so no other site can read responses to authenticated requests.
//
// Aug 2026 — jireta.vercel.app migration:
// Set CORS_ALLOWED_ORIGINS to include the NEW origin, e.g.:
//   supabase secrets set CORS_ALLOWED_ORIGINS=https://jireta.vercel.app,https://lending-jet-five.vercel.app,https://app.jiretaloanscorp.com
// If you forget, the browser blocks every API response with ACAO:null → Dio
// reports DioExceptionType.unknown and the app previously showed "No Internet
// Connection" even though the network was fine (fixed in connectivity_service.dart
// web fast-path). API calls will still fail until CORS is corrected.

const DEV_ALLOWED_ORIGIN = "*";

// Mga origin na PALAGING pinapayagan, bukod pa sa CORS_ALLOWED_ORIGINS env var.
// Ito ang production web domain ng Jireta Loans (www at bare, at ang /login
// page nito). Kailangan itong nasa allow list dahil kapag hindi, bino-block ng
// browser ang LAHAT ng API response (ACAO:null) at ang app ay nagrereport ng
// "No Internet Connection" kahit maayos naman ang network.
//
// Nasa code ito (hindi lang sa secret) para hindi mawala kapag na-overwrite ang
// CORS_ALLOWED_ORIGINS — ligtas itong dagdag dahil ang env var ay pinagsasama
// dito, hindi pinapalitan.
const BUILT_IN_ALLOWED_ORIGINS: string[] = [
  "https://www.jireta.com",
  "https://jireta.com",
  "https://app.jiretaloanscorp.com",
];

/** Ang mga origin na nasa CORS_ALLOWED_ORIGINS secret (WALANG built-ins). */
function configuredOrigins(): string[] {
  const raw = Deno.env.get("CORS_ALLOWED_ORIGINS");
  if (!raw || raw.trim() === "") return [];
  return raw
    .split(",")
    .map((o) => o.trim())
    .filter(Boolean);
}

/**
 * Bukas/dev na mode: walang naka-set na CORS_ALLOWED_ORIGINS, o `*` mismo.
 * Pinananatili nito ang dating pag-uugali — kapag hindi naka-configure, `*` ang
 * isinasagot para patuloy na gumana ang local web/testing. Mahalagang suriin
 * ito KESA sa haba ng listahan, dahil ang built-ins ay laging nasa listahan
 * ngayon (kung hindi, mawawala ang wildcard sa local dev).
 */
function corsUnrestricted(): boolean {
  const configured = configuredOrigins();
  return configured.length === 0 || configured.includes("*");
}

/**
 * Ang buong allow list: CORS_ALLOWED_ORIGINS + ang built-in na production
 * origin. Ang `*` ay nananatiling nag-iisa (wildcard mode).
 */
function allowedOrigins(): string[] {
  if (corsUnrestricted()) return [DEV_ALLOWED_ORIGIN];
  return [...new Set([...configuredOrigins(), ...BUILT_IN_ALLOWED_ORIGINS])];
}

// The value stamped on every JSON response. When CORS is restricted the
// deployment's own web origin is used (single-origin in practice); when
// unconfigured `*` keeps local web/dev working. Mobile apps ignore CORS.
// deno-lint-ignore no-unused-vars
function defaultAllowOrigin(): string {
  if (corsUnrestricted()) return DEV_ALLOWED_ORIGIN;
  return allowedOrigins()[0];
}

export const corsHeaders: Record<string, string> = {
  // Note: this static object is kept for backwards-compat but is NOT used
  // directly for JSON responses anymore — see getCorsHeaders() below.
  // Keeping it as '*' avoids stale first-origin bug when env has multiple origins.
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept, x-idempotency-key, x-session-id",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
};

export function handleCors(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req) });
  }
  return null;
}

// Preflight/OPTIONS response: echo the request's own Origin back only when it
// is on the allow list (a browser rejects a comma-joined ACAO list).
export function corsHeadersFor(req: Request): Record<string, string> {
  const allowed = allowedOrigins();
  // Unconfigured (local dev) o `*` → wildcard
  if (allowed.includes(DEV_ALLOWED_ORIGIN)) return { ...corsHeaders };
  const reqOrigin = req.headers.get("Origin");
  const isAllowed = reqOrigin != null && allowed.includes(reqOrigin);
  const origin = isAllowed ? reqOrigin! : "null";
  return { ...corsHeaders, "Access-Control-Allow-Origin": origin };
}

// Central helper: pick correct ACAO for a JSON response.
// If `req` is provided (preferred) we echo the caller's Origin when allowed.
// If `req` is missing (legacy call sites) we fall back to wildcard when multiple
// origins are configured — this prevents the old bug where every JSON response
// used the *first* origin only and secondary origins (e.g. jireta.vercel.app)
// were always blocked despite being in CORS_ALLOWED_ORIGINS.
function getCorsHeaders(req?: Request): Record<string, string> {
  if (!req) {
    const allowed = allowedOrigins();
    if (allowed.includes(DEV_ALLOWED_ORIGIN)) {
      return { ...corsHeaders };
    }
    // Legacy path: no req to inspect. Returning '*' unblocks all configured
    // origins (secure enough for this app) and fixes the production
    // "cannot connect to server (CORS)" that survived the jireta migration.
    // Once all call sites pass `req`, this branch becomes dead code.
    //
    // Tandaan: ang haba dito ay kasama na ang built-in na production origin,
    // kaya ang branch na ito ay wildcard kahit isang origin lang ang nasa
    // secret. Sinadya ito — ang tanging paraan para siguradong gumana ang
    // www.jireta.com sa LEGACY call sites (na hindi pa nagpapasa ng `req`).
    if (allowed.length > 1) return { ...corsHeaders };
    // Isang origin lang (walang built-in) → keep strict
    return {
      ...corsHeaders,
      "Access-Control-Allow-Origin": allowed[0],
    };
  }
  return corsHeadersFor(req);
}

export function jsonResponse(
  data: unknown,
  status = 200,
  req?: Request,
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
  });
}

// Alias — some functions import successResponse instead of jsonResponse.
export const successResponse = jsonResponse;

export function errorResponse(
  message: string,
  status = 400,
  code?: string,
  extra?: Record<string, unknown>,
  req?: Request,
): Response {
  // errorResponse has an overloaded last arg: if `extra` is a Request (legacy
  // callers that already passed req as 5th arg is handled), detect it.
  // But our signature is (msg,status,code,extra,req) — extra is object, req is Request.
  // To keep backwards compat we allow `extra` to be a Request when code is undefined.
  let actualExtra = extra;
  let actualReq = req;
  // Heuristic: if extra looks like a Request (has 'headers' & 'method'), treat it as req
  if (
    actualExtra != null &&
    typeof actualExtra === "object" &&
    "headers" in (actualExtra as Record<string, unknown>) &&
    "method" in (actualExtra as Record<string, unknown>) &&
    !actualReq
  ) {
    actualReq = actualExtra as unknown as Request;
    actualExtra = undefined;
  }
  return new Response(
    JSON.stringify({
      error: { message, code: code ?? "BAD_REQUEST", ...actualExtra },
    }),
    {
      status,
      headers: {
        ...getCorsHeaders(actualReq),
        "Content-Type": "application/json",
      },
    },
  );
}
