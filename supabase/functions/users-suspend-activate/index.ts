
// supabase/functions/users-suspend-activate/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const { user_id, action } = await req.json();
    if (!user_id || !['suspend', 'activate'].includes(action)) {
      return errorResponse('user_id and action (suspend|activate) are required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: target } = await db.from('users').select('id, account_status, roles(name)').eq('id', user_id).single();
    if (!target) return errorResponse('User not found', 404, 'NOT_FOUND');

    if ((target as any).roles?.name === 'head_manager') {
      return errorResponse('Cannot suspend a Head Manager account', 400, 'FORBIDDEN');
    }

    const newStatus = action === 'suspend' ? 'suspended' : 'active';
    await db.from('users').update({ account_status: newStatus }).eq('id', user_id);

    await writeAuditLog({ performedBy: user.id, action, tableName: 'users', recordId: user_id, oldValues: { account_status: target.account_status }, newValues: { account_status: newStatus }, ipAddress: ip });
    await sendPushNotification({ userId: user_id, title: action === 'suspend' ? 'Account Suspended' : 'Account Activated', body: action === 'suspend' ? 'Your account has been suspended. Contact the office.' : 'Your account has been reactivated.', type: 'account_status_change' });

    return jsonResponse({ message: `User ${action}d successfully` });
  } catch (err) {
    console.error('users-suspend-activate error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
