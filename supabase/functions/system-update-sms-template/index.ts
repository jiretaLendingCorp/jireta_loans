// supabase/functions/system-update-sms-template/index.ts
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
    const { template_id, content } = body;

    if (!template_id || !content) {
        return errorResponse('template_id and content are required', 400, 'VALIDATION_ERROR');
    }

    if (typeof content !== 'string' || content.trim().length === 0) {
        return errorResponse('content must be a non-empty string', 400, 'VALIDATION_ERROR');
    }

    if (content.length > 1600) {
        return errorResponse('SMS content exceeds maximum length of 1600 characters', 400, 'VALIDATION_ERROR');
    }

    const supabase = getAdminClient();

    const { data: existing, error: fetchErr } = await supabase
        .from('sms_templates')
        .select('id, template_key, body')
        .eq('id', template_id)
        .single();

    if (fetchErr || !existing) {
        return errorResponse('SMS template not found', 404, 'NOT_FOUND');
    }

    const { error } = await supabase
        .from('sms_templates')
        .update({
            body: content.trim(),
            updated_at: new Date().toISOString(),
        })
        .eq('id', template_id);

    if (error) return errorResponse('Failed to update SMS template', 500, 'DB_ERROR');

    await writeAuditLog({
        performedBy: authResult.id,
        action: 'sms_template_updated',
        tableName: 'sms_templates',
        recordId: existing.id,
        oldValues: { body: existing.body },
        newValues: { body: content.trim() },
    });

    return jsonResponse({ success: true, template_id, template_key: existing.template_key });
});
