// supabase/functions/_shared/cors.ts
//
// HARDENED: Added 'accept' to Access-Control-Allow-Headers.
// ADDED: successResponse helper used by in-office-submit and similar functions.
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

// Alias — some functions import successResponse instead of jsonResponse.
// Both produce the same 200 JSON envelope so they are interchangeable.
export const successResponse = jsonResponse;

export function errorResponse(message: string, status = 400, code?: string): Response {
  return new Response(
    JSON.stringify({ error: { message, code: code ?? 'BAD_REQUEST' } }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}
