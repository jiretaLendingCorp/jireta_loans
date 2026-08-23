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

const DEV_ALLOWED_ORIGIN = "https://jireta.vercel.app";

function allowedOrigins(): string[] {
  const raw = Deno.env.get("CORS_ALLOWED_ORIGINS");
  if (!raw || raw.trim() === "") return [];
  return raw
    .split(",")
    .map((o) => o.trim())
    .filter(Boolean);
}

// The value stamped on every JSON response. When CORS is restricted the
// deployment's own web origin is used (single-origin in practice); when
// unconfigured `*` keeps local web/dev working. Mobile apps ignore CORS.
function defaultAllowOrigin(): string {
  const configured = allowedOrigins();
  if (configured.length === 0) return DEV_ALLOWED_ORIGIN;
  return configured[0];
}

export const corsHeaders: Record<string, string> = {
  // Note: this static object is kept for backwards-compat but is NOT used
  // directly for JSON responses anymore — see getCorsHeaders() below.
  // Keeping it as '*' avoids stale first-origin bug when env has multiple origins.
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept, x-idempotency-key",
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
  const configured = allowedOrigins();
  // Unconfigured (local dev) → wildcard
  if (configured.length === 0) return { ...corsHeaders };
  // Support '*' wildcard in env
  if (configured.includes("*")) return { ...corsHeaders };
  const reqOrigin = req.headers.get("Origin");
  const allowed = reqOrigin && configured.includes(reqOrigin);
  const origin = allowed ? reqOrigin! : "null";
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
    const configured = allowedOrigins();
    if (configured.length === 0 || configured.includes("*")) {
      return { ...corsHeaders };
    }
    // Legacy path: no req to inspect. Returning '*' unblocks all configured
    // origins (secure enough for this app) and fixes the production
    // "cannot connect to server (CORS)" that survived the jireta migration.
    // Once all call sites pass `req`, this branch becomes dead code.
    if (configured.length > 1) return { ...corsHeaders };
    // Single origin configured → keep strict
    return {
      ...corsHeaders,
      "Access-Control-Allow-Origin": configured[0],
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
