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

  // ── 10-minute idle tracking: bump last_login_at on every authenticated request ──
  // Fire-and-forget so the API response is not delayed. Ensures the server-side
  // 10m idle window in auth-session stays in sync with client idle detector.
  try {
    supabase
      .from('users')
      .update({ last_login_at: nowManilaISO() })
      .eq('id', dbUser.id)
      .then(() => {}, () => {});
  } catch (_) {}

  return {
    id: dbUser.id,
    role: dbUser?.roles?.name ?? '',
    email: user.email,
    phone: user.phone,
  };
}

export function isAuthUser(val: AuthUser | Response): val is AuthUser {
  return !(val instanceof Response);
}
