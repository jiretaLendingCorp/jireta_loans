// supabase/functions/system-get-sms-templates/index.ts
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
        .from('sms_templates')
        .select('*')
        .order('template_key', { ascending: true });

    if (error) return errorResponse('Failed to fetch SMS templates', 500, 'DB_ERROR');

    return jsonResponse({ templates: data ?? [] });
});
