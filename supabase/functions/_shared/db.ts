// supabase/functions/_shared/db.ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.95.0';

export function getAdminClient() {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/**
 * Client na gamit LANG para sa GoTrue sign-in / refresh (`signInWithPassword`,
 * `refreshSession`) — hindi para sa `.from()` / `.rpc()`.
 *
 * Bakit `persistSession: false` + hiwalay na `storageKey`:
 *   Ang mga login function (auth-login / auth-otp / auth-google / auth-session)
 *   ay nag-sign-in sa client na ito, at ang session ng user ay itinatabi ng
 *   supabase-js sa storage ng client. Sa Edge Function isolate (isang proceso
 *   na naglilingkod sa maraming request) ang `localStorage` ay KUNG minsan
 *   available at KUNG minsan hindi — kapag available, isang shared store ito
 *   na `sb-<project-ref>-auth-token` ang key. Sinumang client sa parehong
 *   isolate, kasama ang service-role client na ginagamit para sa
 *   `rpc('claim_active_session')` (service-role-LANG ang grant), ay maaaring
 *   makakuha ng token ng user at tumakbo bilang `authenticated` →
 *   "permission denied for function claim_active_session" (42501) at hindi
 *   kailanman na-a-claim ang session.
 *
 *   Ang `persistSession: false` ay hindi nakakasira sa mga caller: ang
 *   `data.session` na ibinabalik ng sign-in / refresh ay galing sa HTTP
 *   response, hindi sa storage. Tanging ang pag-persist (at ang panganib ng
 *   pag-leak sa ibang client) ang tinatanggal.
 */
export function getAnonClient() {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  return createClient(supabaseUrl, anonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
      storageKey: 'jireta-anon-ephemeral',
    },
  });
}