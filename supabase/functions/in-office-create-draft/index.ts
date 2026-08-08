// supabase/functions/in-office-create-draft/index.ts
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
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();

    const { data: draft, error } = await db
      .from('in_office_applications')
      .insert({
        created_by: authResult.id,
        status: 'draft',
        wizard_step: 1,
      })
      .select()
      .single();

    if (error) return errorResponse('Failed to create draft application', 500, 'DB_ERROR');

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'in_office_draft_created',
      tableName: 'in_office_applications',
      recordId: draft.id,
      newValues: { status: 'draft' },
    });

    return jsonResponse({ success: true, application_id: draft.id, draft });
  } catch (err) {
    console.error('in-office-create-draft error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});