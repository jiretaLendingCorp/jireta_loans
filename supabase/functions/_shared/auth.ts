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
    return errorResponse('Missing or invalid authorization header', 401, 'UNAUTHORIZED');
  }

  const token = authHeader.replace('Bearer ', '');
  const supabase = getAdminClient();

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    return errorResponse('Invalid or expired token', 401, 'UNAUTHORIZED');
  }

  const { data: dbUserRow, error: dbErr } = await supabase
    .from('users')
    .select('id, account_status, roles(name)')
    .eq('id', user.id)
    .single();

  if (dbErr || !dbUserRow) {
    return errorResponse('User not found', 401, 'UNAUTHORIZED');
  }

  const dbUser = singleWithObjectEmbeds(dbUserRow);
  if (!dbUser) {
    return errorResponse('User not found', 401, 'UNAUTHORIZED');
  }

  if (dbUser.account_status === 'archived') {
    return errorResponse('Account is archived', 403, 'ACCOUNT_ARCHIVED');
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