// supabase/functions/_shared/auth.ts
import { getAdminClient } from './db.ts';
import { errorResponse } from './cors.ts';
import { singleWithObjectEmbeds } from './types.ts';
import { nowManilaISO } from './timezone.ts';
import { phoneToE164 } from './validators.ts';

export interface AuthUser {
  id: string;
  role: string;
  email?: string;
  phone?: string;
  sessionIdentifier: string;
}

/**
 * Validates a client-supplied session id (sent at login and on every request
 * via the `X-Session-Id` header / `session_id` body field).
 *
 * The id is generated ONCE per login by the client and kept in secure
 * storage, so it is STABLE across token refreshes. The JWT `session_id`
 * claim is NOT used as the primary identifier because every GoTrue
 * sign-in/refresh can mint a new session id — using it here would make the
 * app falsely revoke its own healthy session the moment its token rotates
 * ("both devices locked out" bug).
 */
export function cleanSessionId(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (trimmed === '' || trimmed.length > 100) return null;
  return trimmed;
}

export function sessionIdentifierFromRequest(
  req: Request,
  token: string,
): string {
  const header = req.headers.get('x-session-id');
  const fromHeader = cleanSessionId(header);
  if (fromHeader) return fromHeader;
  return sessionIdentifierFromToken(token);
}

/**
 * Resulta ng claim: `claimed` = nakuha ng device na ito ang session;
 * `refused` = may SARIWANG session na ibang identifier (first-login-wins —
 * hindi ito nire-revoke, walang row ang bagong device); `error` = RPC/infra
 * error (degraded — fail-open, hindi dapat mag-block ng login).
 *
 * Mahalaga ang pagkakaiba: dati ay boolean lang ito, kaya ang isang REFUSED na
 * claim sa login ay tahimik na pinapasa — nag-login ang app nang "successful"
 * at saka naman SESSION_REVOKED sa kauna-unahang request (lumalabas na
 * "signed in on another device" kahit hindi malinaw kung bakit).
 */
export type SessionClaimOutcome = 'claimed' | 'refused' | 'error';

export async function claimActiveSessionDetailed(
  db: ReturnType<typeof getAdminClient>,
  userId: string,
  sessionIdentifier: string,
): Promise<SessionClaimOutcome> {
  const { data, error } = await db.rpc('claim_active_session', {
    p_user_id: userId,
    p_session_identifier: sessionIdentifier,
  });
  if (error) {
    const message = error.message ?? 'unknown error';
    console.error('[session] claim_active_session failed', message);
    if (message.includes('permission denied')) {
      // 42501 = ang request ay hindi tumatakbo bilang service_role. Karaniwang
      // sanhi: ang admin client na ito ay ginamit sa
      // `signInWithPassword`/`refreshSession`, kaya naging USER-scoped na ito
      // (supabase-js `_getAccessToken()` → session token) at lahat ng kasunod
      // na `.from()`/`.rpc()` ay `authenticated` na ang role. Ang claim ay
      // SERVICE-ROLE-only: gumamit ng hiwalay na `getAnonClient()` para sa
      // sign-in/refresh.
      console.error(
        '[session] claim_active_session 42501 — service-role-only ang claim; huwag i-reuse ang admin client pagkatapos ng signInWithPassword/refreshSession',
      );
    }
    return 'error';
  }
  return data === true ? 'claimed' : 'refused';
}

/** Claim the one active session for a newly issued Supabase session. */
export async function claimActiveSession(
  db: ReturnType<typeof getAdminClient>,
  userId: string,
  sessionIdentifier: string,
): Promise<boolean> {
  return (await claimActiveSessionDetailed(db, userId, sessionIdentifier)) ===
    'claimed';
}


/**
 * Sariwa pa ba ang session (may heartbeat sa loob ng 5 minuto)? Tugma ito sa
 * freshness window ng `claim_active_session` (first-login-wins). Mas matanda
 * sa cutoff = patay na ang device → hindi dapat magpa-logout ng ibang device.
 */
export function freshSessionCutoffISO(): string {
  return new Date(Date.now() - 5 * 60 * 1000).toISOString();
}


export async function requireAuth(req: Request): Promise<AuthUser | Response> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    console.error('[requireAuth] 401 MISSING_HEADER', { path: new URL(req.url).pathname + new URL(req.url).search, hasAuth: !!authHeader, fn: new URL(req.url).searchParams.get('fn') });
    return errorResponse('Missing or invalid authorization header', 401, 'UNAUTHORIZED_MISSING_HEADER');
  }

  const rawToken = authHeader.replace('Bearer ', '').trim();
  if (!rawToken) {
    console.error('[requireAuth] 401 EMPTY_TOKEN', { path: new URL(req.url).pathname + new URL(req.url).search });
    return errorResponse('Missing or invalid authorization header', 401, 'UNAUTHORIZED_EMPTY_TOKEN');
  }

  // Fast-path: anon key is never a valid user session – return distinct code
  // so the client/interceptor can avoid a pointless refresh attempt.
  // Detect via JWT role claim without verifying signature (cheap).
  try {
    const payload = JSON.parse(atob(rawToken.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    if (payload?.role === 'anon') {
      console.error('[requireAuth] 401 ANON_TOKEN', { path: new URL(req.url).pathname + new URL(req.url).search, fn: new URL(req.url).searchParams.get('fn') });
      return errorResponse('Anonymous token not allowed', 401, 'UNAUTHORIZED_ANON_TOKEN');
    }
  } catch (_) {
    // ignore decode failure – fall through to getUser verification
  }

  const token = rawToken;
  // Prefer the client's stable session id (survives token refresh); fall back
  // to the JWT-derived identifier for older clients that predate it.
  const sessionIdentifier = sessionIdentifierFromRequest(req, token);
  const supabase = getAdminClient();

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    console.error('[requireAuth] 401 INVALID_TOKEN', {
      path: new URL(req.url).pathname + new URL(req.url).search,
      fn: new URL(req.url).searchParams.get('fn'),
      error: error?.message ?? 'no user',
      code: (error as unknown as { code?: string })?.code ?? null,
    });
    return errorResponse('Invalid or expired token', 401, 'UNAUTHORIZED_INVALID_TOKEN');
  }

  let { data: dbUserRow, error: dbErr } = await supabase
    .from('users')
    .select('id, account_status, roles!users_role_id_fkey(name)')
    .eq('id', user.id)
    .single();

  if (dbErr || !dbUserRow) {
    const email = user.email?.trim().toLowerCase();

    let identityRow = null;
    let identityErr = null;
    if (email) {
      const result = await supabase
        .from('users')
        .select('id, account_status, roles!users_role_id_fkey(name)')
        .ilike('email', email)
        .maybeSingle();
      identityRow = result.data;
      identityErr = result.error;
    }
    if (!identityRow && user.phone) {
      // Phone in auth.users is E.164 (+639...), but public.users stores local 09... format.
      // Try both canonical forms so legacy mismatched accounts are still resolvable.
      const rawPhone = String(user.phone ?? '').trim();
      const digits = rawPhone.replace(/\D/g, '');
      let localPhone = rawPhone;
      if (digits.startsWith('63')) {
        localPhone = '0' + digits.slice(2);
      } else if (digits.startsWith('0')) {
        localPhone = digits;
      }
      const e164Phone = digits.startsWith('63')
        ? `+${digits}`
        : digits.startsWith('0')
          ? `+63${digits.slice(1)}`
          : `+63${digits}`;
      const candidates = [localPhone, e164Phone, rawPhone].filter(Boolean);
      // Deduplicate
      const uniq = [...new Set(candidates)];
      for (const cand of uniq) {
        const result = await supabase
          .from('users')
          .select('id, account_status, roles!users_role_id_fkey(name)')
          .eq('phone_number', cand)
          .maybeSingle();
        if (result.data) {
          identityRow = result.data;
          identityErr = result.error;
          break;
        }
        // Keep last error for logging, but continue trying next candidate
        identityErr = result.error;
      }
    }

    if (identityRow && !identityErr) {
      console.warn('[requireAuth] auth/public user id mismatch recovered', {
        auth_user_id: user.id,
        public_user_id: identityRow.id,
        email: user.email,
        phone: user.phone,
        path: new URL(req.url).pathname + new URL(req.url).search,
      });
      dbUserRow = identityRow;
      dbErr = null;
    }
  }

  if (dbErr || !dbUserRow) {
    console.error('[requireAuth] 401 USER_NOT_FOUND', {
      userId: user.id,
      email: user.email,
      phone: user.phone,
      dbErr: dbErr?.message ?? null,
      code: (dbErr as unknown as { code?: string })?.code ?? null,
      path: new URL(req.url).pathname + new URL(req.url).search,
    });
    return errorResponse('User not found', 401, 'UNAUTHORIZED_USER_NOT_FOUND');
  }

  const dbUser = singleWithObjectEmbeds(dbUserRow);
  if (!dbUser) {
    console.error('[requireAuth] 401 USER_NOT_FOUND_EMBED', { userId: user.id });
    return errorResponse('User not found', 401, 'UNAUTHORIZED_USER_NOT_FOUND');
  }

  if (dbUser.account_status === 'archived') {
    return errorResponse('Account is archived', 403, 'ACCOUNT_ARCHIVED');
  }

  // TEMP HOTFIX: role-archived check disabled to restore login for all accounts
  // (was blocking all logins due to missing column / archived roles)
  // const roleName = dbUser?.roles?.name as string | undefined;
  // if (roleName) {
  //   try {
  //     const { data: roleRow } = await supabase.from('roles').select('is_archived').eq('name', roleName).maybeSingle();
  //     if ((roleRow as any)?.is_archived === true) return errorResponse('Role is archived — account disabled', 403, 'ROLE_ARCHIVED');
  //   } catch (_) {}
  // }

  if (dbUser.account_status === 'pending') {
    return errorResponse(
      'Account is pending approval',
      403,
      'ACCOUNT_PENDING',
    );
  }

  const sessionIsActive = await supabase.rpc('validate_active_session', {
    p_user_id: dbUser.id,
    p_session_identifier: sessionIdentifier,
  });

  // Fail-open on infrastructure errors. If the RPC itself errors (e.g. the
  // `active_sessions` migration was never applied to this database, or the
  // function/grants are missing), log it loudly and ALLOW the request.
  // Locking every user out of the whole app because single-session
  // enforcement is unavailable is worse than degrading to no enforcement.
  // Only a CLEAN `false` — this session identifier was superseded by a newer
  // login — revokes the device.
  if (sessionIsActive.error) {
    console.error(
      '[requireAuth] validate_active_session RPC error — single-session enforcement degraded, allowing request',
      {
        userId: dbUser.id,
        sessionIdentifier,
        error: sessionIsActive.error.message,
        code: (sessionIsActive.error as { code?: string })?.code ?? null,
      },
    );
  } else if (sessionIsActive.data !== true) {
    // A clean `false` can mean either:
    //   1. This sign-in was superseded by a newer login on another device
    //      (an active_sessions row exists, but with a different identifier)
    //      → genuinely revoked, the ONLY case that returns SESSION_REVOKED.
    //   2. NO row exists for the account at all — the claim at login never
    //      persisted (login function deployed without claims, claim RPC
    //      missing/half-applied, etc.). There is nothing to supersede, so we
    //      must NOT revoke. We also must NOT lazily create the row here:
    //      a lazy claim would revoke OTHER devices whose logins also skipped
    //      the claim, causing false "Session Ended" on every account.
    //      Allow the request (fail-open) and log; the next proper login
    //      claims the session server-side.
    const { data: anyRow, error: anyErr } = await supabase
      .from('active_sessions')
      .select('id')
      .eq('user_id', dbUser.id)
      .maybeSingle();
    if (anyErr) {
      console.error(
        '[requireAuth] active_sessions existence check failed — allowing request',
        {
          userId: dbUser.id,
          error: anyErr.message,
          code: (anyErr as { code?: string })?.code ?? null,
        },
      );
    } else if (!anyRow) {
      // Walang row para sa account na ito — hindi nag-persist ang claim sa
      // login (hindi pa na-deploy ang claim RPC, nag-error ito sa login, o
      // na-delete ng migration). Dito LANG safe ang lazy claim: dahil
      // FIRST-LOGIN-WINS na ang rule, ang `claim_active_session` ay
      // TUMATANGGI kapag may ibang sariwang session (hindi nito nire-revoke
      // ang iba) — at wala ngang row ngayon, kaya walang masisirang session.
      // Kung hindi ito gawin, mananatiling walang single-session enforcement
      // ang account at paulit-ulit ang warning sa bawat request (ping, atbp.).
      const claimed = await claimActiveSession(
        supabase,
        dbUser.id,
        sessionIdentifier,
      );
      console.warn(
        '[requireAuth] validate miss with no active_sessions row — lazily claimed (self-heal)',
        { userId: dbUser.id, sessionIdentifier, claimed },
      );
    } else {
      // May row para sa account pero IBANG session_identifier. Dati, kahit
      // anong mismatch ay SESSION_REVOKED — kaya isang leftover na row mula sa
      // lumang build/install (na wala nang gumagamit) ay nagpapakita ng
      // "signed in on another device" at hindi na mabuksan ang app.
      //
      // Ngayon, tinitiyak muna na BUHAY pa ang ibang session: kapag STALE na
      // ang row nito (walang heartbeat sa loob ng 5 minuto), patay na iyon at
      // hindi dapat makagambala sa buhay na device. Self-heal: i-claim ang row
      // para sa device na ito — tatanggi pa rin ang RPC kapag sariwa ang iba.
      const { data: freshOther, error: freshErr } = await supabase
        .from('active_sessions')
        .select('id, session_identifier, last_seen_at')
        .eq('user_id', dbUser.id)
        .neq('session_identifier', sessionIdentifier)
        .is('revoked_at', null)
        .gt('last_seen_at', freshSessionCutoffISO())
        .maybeSingle();

      if (freshErr) {
        console.error(
          '[requireAuth] freshness check failed — allowing request',
          { userId: dbUser.id, error: freshErr.message },
        );
      } else if (!freshOther) {
        const claimed = await claimActiveSession(
          supabase,
          dbUser.id,
          sessionIdentifier,
        );
        console.warn(
          '[requireAuth] stale active_sessions row for another id — self-healed',
          { userId: dbUser.id, sessionIdentifier, claimed },
        );
        if (!claimed) {
          return errorResponse(
            'Your account was signed in on another device. This session has been logged out for security.',
            401,
            'SESSION_REVOKED',
          );
        }
      } else {
        // Sariwa ang ibang session — tunay na may ibang device na aktibo.
        // Detalyadong log para makita KAAGAD kung sino/may kailan ito huling
        // nakita (ito ang magpapatunay kung tunay ngang ibang device o
        // leftover row lang na patuloy na nag-heheartbeat).
        console.warn('[requireAuth] SESSION_REVOKED — ibang sariwang session', {
          userId: dbUser.id,
          sentSessionIdentifier: sessionIdentifier,
          activeSessionIdentifier: freshOther?.session_identifier ?? null,
          activeLastSeenAt: freshOther?.last_seen_at ?? null,
        });
        return errorResponse(
          'Your account was signed in on another device. This session has been logged out for security.',
          401,
          'SESSION_REVOKED',
        );
      }
    }
  }

  return {
    id: dbUser.id,
    role: dbUser?.roles?.name ?? '',
    email: user.email,
    phone: user.phone,
    sessionIdentifier,
  };
}

export function sessionIdentifierFromToken(token: string): string {
  try {
    const encoded = token.split('.')[1];
    const payload = JSON.parse(atob(encoded.replace(/-/g, '+').replace(/_/g, '/')));
    const value = payload?.session_id ?? payload?.sessionId;
    if (typeof value === 'string' && value.trim() !== '') return value;
  } catch (_) {}
  // Legacy tokens do not expose session_id. They still receive a server-side
  // record and remain compatible until they are refreshed.
  return token;
}

export function isAuthUser(val: AuthUser | Response): val is AuthUser {
  return !(val instanceof Response);
}

/**
 * Metadata para sa GoTrue (`auth.users.raw_user_meta_data`) — ito ang
 * pinagmulan ng **Display name** column sa Supabase Dashboard → Authentication
 * → Users.
 *
 * Hinahango ng Studio ang pangalan mula sa marami-raming key
 * (`display_name`, `name`, `full_name`, `first_name`, `last_name`), kaya
 * isinusulat natin ang lahat ng alam natin. Kung wala nito, `-` ang nakikita
 * ng staff sa dashboard kahit may pangalan naman ang account sa
 * `public.users`.
 *
 * WALANG app logic na umaasa sa metadata na ito (ang app ay sa `public.users`
 * nagbabasa) — display lang ito para sa dashboard/staff.
 */
export function authDisplayMetadata(input: {
  firstName?: string | null;
  lastName?: string | null;
  phone?: string | null;
}): Record<string, string> {
  const first = (input.firstName ?? '').trim();
  const last = (input.lastName ?? '').trim();
  const phone = (input.phone ?? '').trim();
  const fullName = [first, last].filter(Boolean).join(' ');

  const meta: Record<string, string> = {};
  if (fullName) {
    meta.display_name = fullName;
    meta.name = fullName;
    meta.full_name = fullName;
  }
  if (first) meta.first_name = first;
  if (last) meta.last_name = last;
  if (phone) meta.phone = phone;
  return meta;
}

/** Resulta ng [syncAuthUserIdentity]. */
export interface AuthIdentitySync {
  ok: boolean;
  /** May IBANG auth user nang gumagamit ng email o phone — hindi ito naisulat. */
  duplicate: boolean;
  /** Ang PHONE mismo ang gamit na ng ibang auth user (hindi email). */
  phoneDuplicate?: boolean;
  /** Ang `auth.users.email` BAGO ang sync (para sa rollback). */
  previousEmail: string | null;
  error?: string;
}

/**
 * Ipinapantay ang `auth.users` (email + display metadata) sa `public.users`.
 *
 * Bakit kailangan: ang self-registered lender ay may sintetikong
 * `${phone}@jireta.temp` na credential sa GoTrue. Kapag na-verify na niya ang
 * totoong email sa app, `public.users.email` lang ang dating naisusulat — kaya
 * TEMP pa rin ang nakikita sa Auth dashboard, hindi siya makapasok sa Google
 * sign-in (`auth-google` ay tumatanggi sa `@jireta.temp`), at hindi magagamit
 * ng GoTrue (email login / recovery) ang totoong address.
 *
 * Sinusundan din nito ang **phone** sa GoTrue (`auth.users.phone`, E.164) —
 * ito ang ginagamit ng OTP login, kaya kapag pinalitan ng head manager ang
 * `public.users.phone_number` at hindi ito sumunod, wala nang auth user na
 * mahahanap ang `signInWithPassword({ phone })` at "Unable to sign in. Please
 * try again." ang isinasagot ng `auth-otp?fn=verify-otp`.
 *
 * Tumatanggi ito (`duplicate: true`) kapag may ibang auth user nang gumagamit
 * ng email/phone, para hindi magkahati ang `public.users` at `auth.users`.
 */
export async function syncAuthUserIdentity(
  db: ReturnType<typeof getAdminClient>,
  userId: string,
  patch: {
    email?: string | null;
    firstName?: string | null;
    lastName?: string | null;
    phone?: string | null;
  },
): Promise<AuthIdentitySync> {
  const result: AuthIdentitySync = {
    ok: true,
    duplicate: false,
    previousEmail: null,
  };

  let currentEmail: string | null = null;
  let currentPhone: string | null = null;
  let currentMeta: Record<string, unknown> = {};
  try {
    const { data, error } = await db.auth.admin.getUserById(userId);
    if (error) {
      console.error('[auth-identity] getUserById failed', {
        userId,
        msg: error.message,
      });
    } else {
      currentEmail = (data?.user?.email ?? null) as string | null;
      currentPhone = (data?.user?.phone ?? null) as string | null;
      currentMeta = (data?.user?.user_metadata ?? {}) as Record<string, unknown>;
    }
  } catch (e) {
    console.error('[auth-identity] getUserById threw', { userId, msg: String(e) });
  }
  result.previousEmail = currentEmail;

  const update: {
    email?: string;
    email_confirm?: boolean;
    user_metadata?: Record<string, unknown>;
  } = {};

  const email = (patch.email ?? '').trim().toLowerCase();
  if (email && email !== (currentEmail ?? '').trim().toLowerCase()) {
    update.email = email;
    update.email_confirm = true;
  }

  // Merge (hindi replace) para hindi mabura ang metadata ng OAuth provider
  // (hal. avatar/name mula sa Google) sa mga naka-link na account.
  const additions = authDisplayMetadata(patch);
  if (Object.keys(additions).length > 0) {
    update.user_metadata = { ...currentMeta, ...additions };
  }

  const markFailed = (message: string, context: string, isPhone = false) => {
    const msg = message.toLowerCase();
    result.ok = false;
    result.error = message;
    result.duplicate = result.duplicate || msg.includes('already') ||
      msg.includes('duplicate') ||
      msg.includes('exists') ||
      msg.includes('registered');
    if (isPhone && result.duplicate) result.phoneDuplicate = true;
    console.error(`[auth-identity] ${context} failed`, {
      userId,
      duplicate: result.duplicate,
      msg: message,
    });
  };

  if (Object.keys(update).length > 0) {
    try {
      const { error } = await db.auth.admin.updateUserById(userId, update);
      if (error) markFailed(error.message ?? 'update failed', 'updateUserById');
    } catch (e) {
      markFailed(String(e), 'updateUserById');
    }
  }

  // ── Login credential: `auth.users.phone` ─────────────────────────────────
  // Ang OTP login (`auth-otp?fn=verify-otp`) ay sa AUTH phone naghahanap ng
  // session (`signInWithPassword({ phone })`), kaya kapag binago ang numero sa
  // `public.users.phone_number` at nanatili ang luma dito, wala nang
  // mahahanap na credential → "Unable to sign in. Please try again.".
  // Hiwalay na update ito para hindi mabara ng duplicate email sa itaas.
  const nextPhone = phoneToE164(patch.phone);
  if (nextPhone && nextPhone !== (currentPhone ?? '').trim()) {
    try {
      const { error } = await db.auth.admin.updateUserById(userId, {
        phone: nextPhone,
        phone_confirm: true,
      });
      if (error) markFailed(error.message ?? 'phone update failed', 'phone sync', true);
    } catch (e) {
      markFailed(String(e), 'phone sync', true);
    }
  }

  return result;
}
