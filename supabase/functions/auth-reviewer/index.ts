// supabase/functions/auth-reviewer/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// GOOGLE PLAY STORE REVIEWER LOGIN — `POST auth-reviewer?fn=login`
//
// Bakit may hiwalay na entry point:
//   * Ang reviewer accounts ay may tunay na Supabase Auth password, pero WALANG
//     SMS na dumarating sa kanilang numero. Ang normal na `auth-otp` flow ay
//     naka-depende sa SMS gateway, expiration, at resend cooldown — hindi
//     maaaring umasa doon ang Play Store reviewer.
//   * HINDI ito pangalawang authentication system: pareho ang GoTrue sign-in,
//     session claim, MFA state, at response shape ng `auth-otp?fn=verify-otp`.
//     Ang tanging dagdag ay ang SERVER-SIDE allowlist at secret password.
//   * Naka-OFF by default. Kapag hindi naka-set ang `REVIEWER_LOGIN_ENABLED`
//     at ang dalawang account secrets, 404 ang isinasagot — parang walang
//     endpoint. Walang client flag na makakapag-activate nito.
//
// Seguridad:
//   * Ang password ay hindi galing sa Flutter build; nasa Supabase secret.
//   * Ang numero ay dapat nasa allowlist AT ang auth user ay dapat may
//     `app_metadata.reviewer = true` (service-role lang ang makakapagsulat).
//   * Isang account lang ang pwedeng buksan: ang naka-configure na reviewer
//     phone para sa role na iyon.
//   * Ang reviewer session ay naka-flag para sa financial-action guard
//     (`_shared/reviewer.ts`).
//   * Bawat success at failure ay naka-log (auth_logs + security_events).
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getAnonClient } from '../_shared/db.ts';
import {
  claimActiveSessionDetailed,
  cleanSessionId,
  sessionIdentifierFromToken,
} from '../_shared/auth.ts';
import { fetchUserMfaState } from '../_shared/mfa.ts';
import { sanitizeIpAddress } from '../_shared/audit.ts';
import {
  guardRateLimit,
  recordSecurityEvent,
} from '../_shared/rate_limiter.ts';
import {
  maskedReviewerPhone,
  reviewerAccountFor,
  reviewerConfigFromEnv,
  reviewerLoginFailedResponse,
  reviewerPasswordMatches,
  type ReviewerAccount,
} from '../_shared/reviewer.ts';
import { singleWithObjectEmbeds } from '../_shared/types.ts';
import { nowManilaISO } from '../_shared/timezone.ts';
import { normalizePhMobile, phoneToE164 } from '../_shared/validators.ts';

const MAX_BODY_CHARS = 4096;

/** Per-IP at per-account na limitasyon laban sa password brute force. */
const REVIEWER_IP_RATE_MAX = 30;
const REVIEWER_ACCOUNT_RATE_MAX = 20;
const REVIEWER_RATE_WINDOW_MINUTES = 15;
const REVIEWER_BLOCK_MINUTES = 15;

function clientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  // Tanging POST — walang reviewer data sa GET/query string.
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 405, 'METHOD_NOT_ALLOWED');
  }

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? 'login';
    if (fn !== 'login') return errorResponse('Not found', 404, 'NOT_FOUND');
    return await handleReviewerLogin(req);
  } catch (err) {
    console.error('[auth-reviewer] unhandled error:', (err as Error)?.message ?? err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

async function handleReviewerLogin(req: Request): Promise<Response> {
  const config = reviewerConfigFromEnv();
  // Disabled → 404. Hindi inihahayag na may reviewer endpoint sa deployment.
  if (!config.enabled) {
    return errorResponse('Not found', 404, 'NOT_FOUND');
  }

  const ip = clientIp(req);
  const ipGuard = await guardRateLimit({
    key: `reviewer:login:ip:${ip}`,
    maxAttempts: REVIEWER_IP_RATE_MAX,
    windowMinutes: REVIEWER_RATE_WINDOW_MINUTES,
    blockMinutes: REVIEWER_BLOCK_MINUTES,
    blockReason: 'Too many reviewer login attempts',
    eventType: 'reviewer_login_rate_limited',
    ipAddress: ip,
  });
  if (!ipGuard.allowed) {
    return errorResponse(
      'Too many sign-in attempts. Try again later.',
      429,
      'REVIEWER_RATE_LIMITED',
    );
  }

  const rawBody = await req.text().catch(() => '');
  if (rawBody.length > MAX_BODY_CHARS) {
    return errorResponse('Request body too large', 413, 'PAYLOAD_TOO_LARGE');
  }
  let body: Record<string, unknown> = {};
  try {
    const parsed = JSON.parse(rawBody || '{}');
    if (parsed && typeof parsed === 'object') {
      body = parsed as Record<string, unknown>;
    }
  } catch (_) {
    return errorResponse('Invalid JSON body', 400, 'VALIDATION_ERROR');
  }

  // `identifier` ay tinatanggap din para pareho ang field sa OTP login, pero
  // numero lang ang valid — walang email reviewer account.
  const rawPhone = String(body['phone'] ?? body['identifier'] ?? '');
  const phone = normalizePhMobile(rawPhone);
  const password = String(body['password'] ?? '').trim();

  const account = phone
    ? reviewerAccountFor(config, phone)
    : null;

  if (!account) {
    // Dummy comparison para hindi kapansin-pansin ang bilis ng pagtanggi.
    reviewerPasswordMatches(null, password);
    console.warn(
      `[auth-reviewer] rejected (reason=not_allowlisted, phone=${
        phone ? maskedReviewerPhone(phone) : 'invalid'
      })`,
    );
    await recordSecurityEvent({
      eventType: 'reviewer_login_failed',
      key: `reviewer:login:ip:${ip}`,
      ipAddress: ip,
      detail: {
        reason: 'not_allowlisted',
        phone: phone ? maskedReviewerPhone(phone) : 'invalid',
      },
    });
    return reviewerLoginFailedResponse();
  }

  const accountGuard = await guardRateLimit({
    key: `reviewer:login:account:${account.role}`,
    maxAttempts: REVIEWER_ACCOUNT_RATE_MAX,
    windowMinutes: REVIEWER_RATE_WINDOW_MINUTES,
    blockMinutes: REVIEWER_BLOCK_MINUTES,
    blockReason: 'Too many reviewer login attempts for this account',
    eventType: 'reviewer_login_rate_limited',
    ipAddress: ip,
  });
  if (!accountGuard.allowed) {
    return errorResponse(
      'Too many sign-in attempts. Try again later.',
      429,
      'REVIEWER_RATE_LIMITED',
    );
  }

  const db = getAdminClient();

  const { data: userRow } = await db
    .from('users')
    .select(
      'id, account_status, email, first_name, last_name, phone_number, force_password_change, roles!users_role_id_fkey(name)',
    )
    .eq('phone_number', account.phone)
    .maybeSingle();
  const user = singleWithObjectEmbeds(userRow);

  const failLogin = async (
    reason: string,
    userId?: string | null,
    context?: Record<string, unknown>,
  ) => {
    // Walang password/OTP sa log line — role, masked phone, at reason lang.
    console.warn(
      `[auth-reviewer] rejected (reason=${reason}, role=${account.role}, phone=${
        maskedReviewerPhone(account.phone)
      }${userId ? `, user_id=${userId}` : ''}${
        context ? `, ${JSON.stringify(context)}` : ''
      })`,
    );
    if (userId) {
      try {
        await db.from('auth_logs').insert({
          user_id: userId,
          event_type: 'reviewer_login_failed',
          ip_address: sanitizeIpAddress(req.headers.get('x-forwarded-for')),
        });
      } catch (_) {
        // Best-effort: kung hindi pa applied ang 00194 migration, huwag
        // harangin ang reviewer (generic failure pa rin ang sagot).
      }
    }
    await recordSecurityEvent({
      eventType: 'reviewer_login_failed',
      key: `reviewer:login:${account.role}`,
      userId: userId ?? null,
      ipAddress: ip,
      detail: {
        reason,
        role: account.role,
        phone: maskedReviewerPhone(account.phone),
        ...(context ?? {}),
      },
    });
    return reviewerLoginFailedResponse();
  };

  if (!user) return await failLogin('missing_public_user');
  if (user.account_status === 'archived' || user.account_status === 'inactive') {
    return await failLogin('account_not_active', user.id);
  }
  if (user?.roles?.name !== account.role) {
    return await failLogin('role_mismatch', user.id);
  }

  // ── Second layer ng allowlist: auth user metadata ──────────────────────────
  // Kahit ma-leak ang secret at mapalitan ang env phone, hindi mabubuksan ng
  // reviewer login ang isang normal na account — kailangan din ng
  // `app_metadata.reviewer` na service-role lang ang makakapagsulat.
  const { data: authData, error: authErr } = await db.auth.admin.getUserById(
    user.id,
  );
  const authUser = authData?.user;
  const appMetadata = (authUser?.app_metadata ?? {}) as Record<string, unknown>;
  if (
    authErr ||
    !authUser ||
    appMetadata['reviewer'] !== true ||
    appMetadata['reviewer_role'] !== account.role
  ) {
    return await failLogin('not_provisioned_as_reviewer', user.id);
  }

  // Ang auth users row ay dapat naka-tali sa configured na reviewer number.
  // Tumatanggap ang phone check ng E.164/local/normalized na format via
  // `normalizePhMobile`. Kapag NAKA-DISABLE ang Phone provider sa project, ang
  // `auth.users.phone` ay maaaring NULL — kaya tinatanggap din ang internal na
  // `${phone}@jireta.temp` email credential na isinusulat ng setup script
  // (pareho ring credential ang ginagamit ng sign-in fallback).
  const authPhone = normalizePhMobile(String(authUser.phone ?? ''));
  const expectedTempEmail = `${account.phone}@jireta.temp`;
  const authEmail = String(authUser.email ?? '').trim().toLowerCase();
  const authEmailMatches = authEmail === expectedTempEmail;
  const identityMatches = authPhone === account.phone || authEmailMatches;
  if (!identityMatches) {
    return await failLogin('phone_mismatch', user.id, {
      auth_phone: authPhone ? maskedReviewerPhone(authPhone) : 'missing',
      auth_email_matches: authEmailMatches,
    });
  }

  if (!reviewerPasswordMatches(account, password)) {
    return await failLogin('bad_password', user.id);
  }

  const session = await signInReviewer(account);
  if (!session) {
    await failLogin('sign_in_failed', user.id);
    return errorResponse(
      'Reviewer sign-in is temporarily unavailable. Please try again.',
      503,
      'REVIEWER_SIGN_IN_FAILED',
    );
  }

  // Huwag kailanman magbigay ng session para sa IBANG auth identity kaysa sa
  // na-validate na public user (legacy id desync / credential mix-up).
  if (session.user?.id && session.user.id !== user.id) {
    await failLogin('auth_user_mismatch', user.id);
    return errorResponse(
      'Reviewer sign-in is temporarily unavailable. Please try again.',
      503,
      'REVIEWER_SIGN_IN_FAILED',
    );
  }

  // ── Single-active-session (kapareho ng OTP login) ─────────────────────────
  try {
    const claim = await claimActiveSessionDetailed(
      db,
      user.id,
      cleanSessionId(body['session_id']) ??
        sessionIdentifierFromToken(session.access_token),
    );
    if (claim === 'refused') {
      return errorResponse(
        'This account is already signed in on another device. Log out from that device first, then sign in again.',
        409,
        'SESSION_ACTIVE_ELSEWHERE',
      );
    }
    if (claim === 'error') {
      console.warn('[auth-reviewer] claimActiveSession degraded — allowing login');
    }
  } catch (e) {
    console.warn('[auth-reviewer] claimActiveSession failed', e);
  }

  // ── Reviewer activity log ─────────────────────────────────────────────────
  try {
    await db.from('auth_logs').insert({
      user_id: user.id,
      event_type: 'reviewer_login',
      ip_address: sanitizeIpAddress(req.headers.get('x-forwarded-for')),
    });
  } catch (_) {
    // Best-effort kung hindi pa applied ang constraint migration.
  }
  await db
    .from('users')
    .update({ last_login_at: nowManilaISO() })
    .eq('id', user.id);
  await recordSecurityEvent({
    eventType: 'reviewer_login_success',
    key: `reviewer:login:${account.role}`,
    userId: user.id,
    ipAddress: ip,
    detail: { role: account.role, phone: maskedReviewerPhone(account.phone) },
  });

  // Walang password, OTP, o token sa log line.
  console.info(
    `[auth-reviewer] login ok (role=${account.role}, user_id=${user.id}, phone=${maskedReviewerPhone(account.phone)})`,
  );

  const mfaState = await fetchUserMfaState(db, user.id);
  const verifiedFactors = mfaState.factors.filter(
    (factor) => factor.status === 'verified',
  );

  return jsonResponse({
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    user: {
      id: user.id,
      phone: account.phone,
      role: user?.roles?.name,
      first_name: user?.first_name ?? '',
      last_name: user?.last_name ?? '',
      phone_number: user?.phone_number ?? account.phone,
      force_password_change: user?.force_password_change,
    },
    // Non-secret na metadata. Ginagamit ito ng app para ipakita ang reviewer
    // banner; ang financial guard ay server-side pa rin.
    reviewer: true,
    reviewer_role: account.role,
    mfa: {
      enabled: mfaState.ok ? verifiedFactors.length > 0 : null,
      factors: mfaState.ok
        ? verifiedFactors.map((factor) => ({
          id: factor.id,
          friendly_name: factor.friendly_name,
        }))
        : [],
    },
  });
}

/**
 * GoTrue sign-in gamit ang SERVER-SIDE password (hindi ang isinumite ng
 * client — `reviewerPasswordMatches` na ang nagpatunay doon). Sinusubukan ang
 * phone credential una, tapos ang `@jireta.temp` email credential, para
 * gumana rin sa project na naka-disable ang Phone provider.
 */
async function signInReviewer(account: ReviewerAccount) {
  const anon = getAnonClient();
  const e164 = phoneToE164(account.phone);
  const tempEmail = `${account.phone}@jireta.temp`;

  for (const credentials of [
    { phone: e164 },
    { email: tempEmail },
  ]) {
    try {
      const { data, error } = await anon.auth.signInWithPassword({
        ...credentials,
        password: account.password,
      });
      if (!error && data?.session) return data.session;
      if (error) {
        console.error(
          `[auth-reviewer] signInWithPassword failed (${'phone' in credentials ? 'phone' : 'email'}):`,
          error.message,
        );
      }
    } catch (e) {
      console.error(
        '[auth-reviewer] signInWithPassword threw:',
        (e as Error)?.message ?? e,
      );
    }
  }
  return null;
}
