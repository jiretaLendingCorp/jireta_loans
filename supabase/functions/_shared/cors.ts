// supabase/functions/_shared/cors.ts
//
// HARDENED: Added 'accept' to Access-Control-Allow-Headers.
// ADDED: successResponse helper used by in-office-submit and similar functions.
// SECURITY: Access-Control-Allow-Origin is restricted to the configured app
// origin. In dev (CORS_ALLOWED_ORIGINS unset) `*` is kept so local Flutter
// web/testing keeps working; in production set CORS_ALLOWED_ORIGINS to the real
// web origin so no other site can read responses to authenticated requests.

const DEV_ALLOWED_ORIGIN = '*';

function allowedOrigins(): string[] {
  const raw = Deno.env.get('CORS_ALLOWED_ORIGINS');
  if (!raw || raw.trim() === '') return [];
  return raw
    .split(',')
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
  'Access-Control-Allow-Origin': defaultAllowOrigin(),
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, accept, x-idempotency-key',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, PUT, DELETE, OPTIONS',
};

export function handleCors(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeadersFor(req) });
  }
  return null;
}

// Preflight/OPTIONS response: echo the request's own Origin back only when it
// is on the allow list (a browser rejects a comma-joined ACAO list).
function corsHeadersFor(req: Request): Record<string, string> {
  const configured = allowedOrigins();
  let origin = defaultAllowOrigin();
  if (configured.length > 0) {
    const reqOrigin = req.headers.get('Origin');
    origin = reqOrigin && configured.includes(reqOrigin) ? reqOrigin : 'null';
  }
  return { ...corsHeaders, 'Access-Control-Allow-Origin': origin };
}

export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Alias — some functions import successResponse instead of jsonResponse.
// Both produce the same 200 JSON envelope so they are interchangeable.
export const successResponse = jsonResponse;

export function errorResponse(message: string, status = 400, code?: string): Response {
  return new Response(
    JSON.stringify({ error: { message, code: code ?? 'BAD_REQUEST' } }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}
