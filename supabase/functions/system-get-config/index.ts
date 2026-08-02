// supabase/functions/system-get-config/index.ts
import { isAuthUser, requireAuth } from '../_shared/auth.ts';
import { errorResponse, handleCors, jsonResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { enforceRole } from '../_shared/rbac.ts';

Deno.serve(async (req: Request) => {
    const cors = handleCors(req);
    if (cors) return cors;

    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;

    const roleCheck = enforceRole(authResult, ['head_manager']);
    if (roleCheck) return roleCheck;

    const supabase = getAdminClient();

    const { data, error } = await supabase
        .from('system_configs')
        .select('*')
        .order('config_key', { ascending: true });

    if (error) return errorResponse('Failed to fetch system config', 500, 'DB_ERROR');

    return jsonResponse({ configs: data ?? [] });
});
