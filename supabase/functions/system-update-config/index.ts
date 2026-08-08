// supabase/functions/system-update-config/index.ts
import { writeAuditLog } from '../_shared/audit.ts';
import { isAuthUser, requireAuth } from '../_shared/auth.ts';
import { errorResponse, handleCors, jsonResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';

Deno.serve(async (req: Request) => {
    const cors = handleCors(req);
    if (cors) return cors;

    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;

    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { config_key, config_value } = body;

    if (!config_key || config_value === undefined || config_value === null) {
        return errorResponse('config_key and config_value are required', 400, 'VALIDATION_ERROR');
    }

    if (typeof config_key !== 'string' || config_key.trim().length === 0) {
        return errorResponse('Invalid config_key', 400, 'VALIDATION_ERROR');
    }

    const supabase = getAdminClient();

    const { data: existing, error: fetchErr } = await supabase
        .from('system_config')
        .select('id, config_key, config_value')
        .eq('config_key', config_key.trim())
        .single();

    if (fetchErr || !existing) {
        return errorResponse('Config key not found', 404, 'NOT_FOUND');
    }

    const { error } = await supabase
        .from('system_config')
        .update({
            config_value: String(config_value),
            updated_at: new Date().toISOString(),
            updated_by: authResult.id,
        })
        .eq('config_key', config_key.trim());

    if (error) return errorResponse('Failed to update config', 500, 'DB_ERROR');

    await writeAuditLog({
        performedBy: authResult.id,
        action: 'system_config_updated',
        tableName: 'system_config',
        recordId: existing.id,
        oldValues: { config_value: existing.config_value },
        newValues: { config_value: String(config_value) },
    });

    return jsonResponse({ success: true, config_key, config_value: String(config_value) });
});
