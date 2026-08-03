// supabase/functions/_shared/cors.ts
//
// HARDENED: Added 'accept' to Access-Control-Allow-Headers.
// Dio sends `Accept: application/json` as a default header.  Even though
// browsers treat `Accept` as a "safelisted" CORS header (no preflight
// needed), some stricter browser configurations or proxy layers do include it
// in Access-Control-Request-Headers.  Listing it explicitly is zero-cost and
// prevents subtle preflight rejections in those environments.
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, accept, x-idempotency-key',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, PUT, DELETE, OPTIONS',
};

export function handleCors(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  return null;
}

export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export function errorResponse(message: string, status = 400, code?: string): Response {
  return new Response(
    JSON.stringify({ error: { message, code: code ?? 'BAD_REQUEST' } }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}
