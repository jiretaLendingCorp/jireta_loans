// supabase/functions/system-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   system-get-config            →  ?fn=get-config
//   system-get-sms-templates     →  ?fn=get-sms-templates
//   system-update-sms-template   →  ?fn=update-sms-template
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { isAuthUser, requireAuth } from '../_shared/auth.ts';
import { errorResponse, handleCors, jsonResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { writeAuditLog } from '../_shared/audit.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-config';

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'get-config':
        // ── [moved from functions/system-get-config/index.ts] ─────────
        return await handleGetConfig(req);
      case 'get-sms-templates':
        // ── [moved from functions/system-get-sms-templates/index.ts] ──
        return await handleGetSmsTemplates(req);
      case 'update-sms-template':
        // ── [moved from functions/system-update-sms-template/index.ts] ─
        return await handleUpdateSmsTemplate(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('system-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/system-get-config/index.ts] ───────────────────────
async function handleGetConfig(req: Request) {
    const cors = handleCors(req);
    if (cors) return cors;

    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;

    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const supabase = getAdminClient();

    const { data, error } = await supabase
        .from('system_config')
        .select('*')
        .order('config_key', { ascending: true });

    if (error) return errorResponse('Failed to fetch system config', 500, 'DB_ERROR');

    return jsonResponse({ configs: data ?? [] });
}

// ── [moved from functions/system-get-sms-templates/index.ts] ────────────────
async function handleGetSmsTemplates(req: Request) {
    const cors = handleCors(req);
    if (cors) return cors;

    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;

    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const supabase = getAdminClient();

    const { data, error } = await supabase
        .from('sms_templates')
        .select('*')
        .order('template_key', { ascending: true });

    if (error) return errorResponse('Failed to fetch SMS templates', 500, 'DB_ERROR');

    return jsonResponse({ templates: data ?? [] });
}

// ── [moved from functions/system-update-sms-template/index.ts] ──────────────
async function handleUpdateSmsTemplate(req: Request) {
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
}