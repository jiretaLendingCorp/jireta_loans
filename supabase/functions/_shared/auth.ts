// supabase/functions/_shared/auth.ts
import { getAdminClient } from './db.ts';
import { errorResponse } from './cors.ts';
import { singleWithObjectEmbeds } from './types.ts';

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
    .select('id, account_status, roles(name, is_archived)')
    .eq('id', user.id)
    .single();

  if (dbErr || !dbUserRow) {
    const email = user.email?.trim().toLowerCase();

    let identityRow = null;
    let identityErr = null;
    if (email) {
      const result = await supabase
        .from('users')
        .select('id, account_status, roles(name, is_archived)')
        .ilike('email', email)
        .maybeSingle();
      identityRow = result.data;
      identityErr = result.error;
    }
    if (!identityRow && user.phone) {
      const result = await supabase
        .from('users')
        .select('id, account_status, roles(name, is_archived)')
        .eq('phone_number', user.phone)
        .maybeSingle();
      identityRow = result.data;
      identityErr = result.error;
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

  if (dbUser?.roles?.is_archived === true) {
    return errorResponse('Role is archived — account disabled', 403, 'ROLE_ARCHIVED');
  }

  if (dbUser.account_status === 'pending') {
    return errorResponse(
      'Account is pending approval',
      403,
      'ACCOUNT_PENDING',
    );
  }

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
