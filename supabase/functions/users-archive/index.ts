
// supabase/functions/users-archive/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const { user_id } = await req.json();
    if (!user_id) return errorResponse('user_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: target } = await db.from('users').select('id, account_status, roles(name)').eq('id', user_id).single();
    if (!target) return errorResponse('User not found', 404, 'NOT_FOUND');
    if ((target as any).roles?.name === 'head_manager') return errorResponse('Cannot archive a Head Manager', 400, 'FORBIDDEN');
    if (target.account_status === 'archived') return errorResponse('User already archived', 400, 'INVALID_STATUS');

    const { count: activeLoans } = await db.from('loans').select('*', { count: 'exact', head: true })
      .eq('user_id', user_id).in('status', ['pending', 'under_review', 'active', 'overdue']);
    if ((activeLoans ?? 0) > 0) return errorResponse('Cannot archive user with active loans', 400, 'ACTIVE_LOAN_EXISTS');

    await db.from('users').update({ account_status: 'archived' }).eq('id', user_id);
    await writeAuditLog({ performedBy: user.id, action: 'archive_user', tableName: 'users', recordId: user_id, ipAddress: ip });

    return jsonResponse({ message: 'User archived successfully' });
  } catch (err) {
    console.error('users-archive error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});