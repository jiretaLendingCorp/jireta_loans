// supabase/functions/in-office-save-step/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { application_id, step, data } = body;

    if (!application_id || !step || !data) {
      return errorResponse('application_id, step, and data are required', 400, 'MISSING_FIELDS');
    }
    if (step < 1 || step > 5) {
      return errorResponse('step must be between 1 and 5', 400, 'INVALID_STEP');
    }

    const db = getAdminClient();

    const { data: app, error: fetchErr } = await db
      .from('in_office_applications')
      .select('id, created_by, status')
      .eq('id', application_id)
      .single();

    if (fetchErr || !app) return errorResponse('Application not found', 404, 'NOT_FOUND');
    if (authResult.role === ROLES.EMPLOYEE && app.created_by !== authResult.id) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }
    if (app.status === 'converted') {
      return errorResponse('Cannot edit a converted application', 422, 'ALREADY_CONVERTED');
    }

    const stepCol = `step${step}_data`;
    const updatePayload: Record<string, unknown> = {
      [stepCol]: data,
      wizard_step: step,
      updated_at: new Date().toISOString(),
    };

    const { data: updated, error: updateErr } = await db
      .from('in_office_applications')
      .update(updatePayload)
      .eq('id', application_id)
      .select()
      .single();

    if (updateErr) return errorResponse('Failed to save step', 500, 'DB_ERROR');

    return jsonResponse({ success: true, application: updated });
  } catch (err) {
    console.error('in-office-save-step error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});