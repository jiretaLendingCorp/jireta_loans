// supabase/functions/_shared/auth.ts
import { getAdminClient } from './db.ts';
import { errorResponse } from './cors.ts';
import { singleWithObjectEmbeds } from './types.ts';
import { nowManilaISO } from './timezone.ts';

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

/** Claim the one active session for a newly issued Supabase session. */
export async function claimActiveSession(
  db: ReturnType<typeof getAdminClient>,
  userId: string,
  sessionIdentifier: string,
): Promise<boolean> {
  const { data, error } = await db.rpc('claim_active_session', {
    p_user_id: userId,
    p_session_identifier: sessionIdentifier,
  });
  if (error) {
    console.error('[session] claim_active_session failed', error.message);
    return false;
  }
  return data === true;
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
      console.warn(
        '[requireAuth] validate miss with no active_sessions row — allowing (enforcement degraded, no lazy claim)',
        { userId: dbUser.id, sessionIdentifier },
      );
    } else {
      return errorResponse(
        'Your account was signed in on another device. This session has been logged out for security.',
        401,
        'SESSION_REVOKED',
      );
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
