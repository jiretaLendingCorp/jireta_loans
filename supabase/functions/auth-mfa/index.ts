// supabase/functions/auth-mfa/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — `?fn=<action>`
//
//   auth-mfa?fn=status  →  server-authoritative na MFA (TOTP) status ng
//                          naka-login na account: may verified factor ba,
//                          ano ang `aal` ng session, at aling operasyon ang
//                          nangangailangan ng `aal2`.
//
// ── Bakit ito kailangan kahit may Supabase client sa Flutter?
// Ang enrollment / challenge / verify ay dumadaan sa SUPABASE AUTH MFA API
// (`mfa.enroll`, `mfa.challenge`, `mfa.verify`, `mfa.unenroll`) — hindi
// dinodoble dito. Ang function na ito ay para sa STATUS at PATOKARAN:
//
//   * ang profile card ay may server-side na pinagmumulan ng katotohanan (hindi
//     nakasalalay sa kung naka-load ba ang session ng Supabase client);
//   * ang server mismo ang nagsasabi kung `aal2` ang kailangan ng mga
//     sensitibong aksyon — kaparehong helper (`_shared/mfa.ts`) na ginagamit ng
//     `users-manage` (palit ng numero) at `auth-mpin` (set/reset).
//
// ── Ano ang HINDI ginagawa ng function na ito (sa disenyo)
//
//   * HINDI ito nag-e-enroll o nagve-verify ng code: ang verification ay nasa
//     GoTrue, at ang session ng user mismo ang nagmamarka ng `aal2`.
//   * HINDI ito nagbibigay ng paraan para i-off ang 2FA nang walang code:
//     ang `unenroll` ng verified factor ay tumatanggi sa `aal1` (GoTrue), at
//     ang naka-audit na HM reset (`users-admin?fn=reset-mfa`) ang tanging
//     recovery path.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { getAdminClient } from '../_shared/db.ts';
import { fetchUserMfaState } from '../_shared/mfa.ts';
import { guardRateLimit } from '../_shared/rate_limiter.ts';

// Abuse protection: sapat para sa normal na pagbubukas ng profile (status lang
// ang binabasa) pero hindi para sa enumeration/polling.
const STATUS_RATE_MAX = 30;
const STATUS_RATE_WINDOW_MINUTES = 10;

const DEFAULT_ACTION = 'status';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'status':
        return await handleStatus(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('auth-mfa error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

async function handleStatus(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const limit = await guardRateLimit({
    key: `auth-mfa:status:${user.id}`,
    maxAttempts: STATUS_RATE_MAX,
    windowMinutes: STATUS_RATE_WINDOW_MINUTES,
    blockMinutes: 10,
    blockReason: 'too many MFA status requests',
    eventType: 'mfa_status_rate_limited',
    userId: user.id,
    ipAddress: req.headers.get('x-forwarded-for') ?? null,
  });
  if (!limit.allowed) {
    return errorResponse(
      'Too many requests. Please try again in a few minutes.',
      429,
      'RATE_LIMITED',
      { retry_after_seconds: limit.block?.retryAfterSeconds ?? 0 },
    );
  }

  const db = getAdminClient();
  const state = await fetchUserMfaState(db, user.id);
  const aal = user.aal ?? 'aal1';

  if (!state.ok) {
    // Hindi matukoy: huwag mag-imbento ng status. Ang client ay may sariling
    // (Supabase Auth) na daan para sa status, at ang mga sensitibong aksyon ay
    // fail-closed (503 MFA_CHECK_FAILED).
    return errorResponse(
      'We could not load your two-factor authentication status. Please try again.',
      503,
      'MFA_CHECK_FAILED',
    );
  }

  return jsonResponse({
    // Verified TOTP factor ba ang naka-enroll sa GoTrue?
    enabled: state.enrolled,
    // Tanging NON-secret na metadata (id / pangalan / status) — walang secret,
    // walang QR, walang setup key.
    factors: state.factors,
    current_level: aal,
    // Kapag may verified factor pero `aal1` pa ang session, kailangan muna ng
    // authenticator code bago ang mga aksyon sa ibaba.
    next_level: state.enrolled ? 'aal2' : aal,
    requires_challenge: state.enrolled && aal !== 'aal2',
    // Ang deklaradong patakaran ng server (tingnan ang paliwanag sa
    // `_shared/mfa.ts`): hindi lahat ng endpoint ay nangangailangan ng `aal2`.
    policy: {
      sensitive_ops_require_aal2_when_enrolled: true,
      sensitive_ops: [
        'users-manage?fn=update-profile (sariling phone_number)',
        'auth-mpin?fn=set',
        'auth-mpin?fn=reset',
        'auth-mfa (2FA disable — GoTrue `mfa.unenroll` ay aal2-only)',
      ],
    },
  });
}
