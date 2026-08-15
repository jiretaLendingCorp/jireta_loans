// supabase/functions/ci-manage/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   ci-assign    →  ?fn=assign
//   ci-accept    →  ?fn=accept
//   ci-decline   →  ?fn=decline
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { validateUUID, sanitizeString } from '../_shared/validators.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'assign';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'assign':
        // ── [moved from functions/ci-assign/index.ts] ───────────────────
        return await handleCiAssign(req);
      case 'accept':
        // ── [moved from functions/ci-accept/index.ts] ───────────────────
        return await handleCiAccept(req);
      case 'decline':
        // ── [moved from functions/ci-decline/index.ts] ──────────────────
        return await handleCiDecline(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('ci-manage error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/ci-assign/index.ts] ───────────────────────────
async function handleCiAssign(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const { loan_id, rider_id, investigation_notes, deadline } = await req.json();

  if (!loan_id || !rider_id) return errorResponse('loan_id and rider_id are required', 400, 'VALIDATION_ERROR');
  if (!validateUUID(loan_id) || !validateUUID(rider_id)) return errorResponse('Invalid UUID format', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();

  const { data: loan } = await db
    .from('loans')
    .select('id, status, lender_id')
    .eq('id', loan_id)
    .single();

  if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  if (!['pending', 'under_review', 'ci_required', 'ci_assigned'].includes(loan.status)) {
    return errorResponse('Loan must be pending or under_review to assign CI', 409, 'INVALID_STATUS');
  }

  const { data: rider } = await db
    .from('rider_profiles')
    .select('id, is_available')
    .eq('id', rider_id)
    .single();

  if (!rider) return errorResponse('Rider not found', 404, 'NOT_FOUND');
  if (!rider.is_available) return errorResponse('Rider is not available', 409, 'RIDER_UNAVAILABLE');

  const { data: ci, error: ciErr } = await db.from('credit_investigations').insert({
    loan_id,
    rider_id,
    assigned_by: authResult.id,
    investigation_notes: investigation_notes ? sanitizeString(investigation_notes) : null,
    deadline: deadline ?? null,
    status: 'assigned',
  }).select().single();

  if (ciErr || !ci) return errorResponse('Failed to create CI assignment', 500, 'SERVER_ERROR');

  await db.from('loans').update({ status: 'ci_assigned' }).eq('id', loan_id);
  await db.from('rider_profiles').update({ is_available: false }).eq('id', rider_id);

  await writeAuditLog({
    performedBy: authResult.id,
    action: 'ci_assigned',
    tableName: 'credit_investigations',
    recordId: ci.id,
    newValues: { loan_id, rider_id, assigned_by: authResult.id },
    ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
  });

  await sendPushNotification({
    userId: rider_id,
    title: 'New CI Assignment',
    body: 'You have been assigned a credit investigation. Tap to view details.',
    type: 'ci_assigned',
    referenceId: ci.id,
    sentBy: authResult.id,
  });

  await sendPushNotification({
    userId: authResult.id,
    title: 'CI Assignment Confirmed',
    body: `Credit investigation assigned to rider successfully.`,
    type: 'ci_assigned',
    referenceId: ci.id,
    sentBy: authResult.id,
  });

  return jsonResponse({ ci_id: ci.id, message: 'CI assigned successfully' }, 201);
}

// ── [moved from functions/ci-accept/index.ts] ───────────────────────────
async function handleCiAccept(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.RIDER);
  if (roleCheck) return roleCheck;
  const { ci_id } = await req.json();
  if (!ci_id) return errorResponse('ci_id is required', 400, 'VALIDATION_ERROR');
  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
  const { data: ci } = await db.from('credit_investigations').select('id, status, assigned_by, rider_id, loan_id').eq('id', ci_id).eq('rider_id', user.id).single();
  if (!ci) return errorResponse('CI assignment not found', 404, 'NOT_FOUND');
  if (ci.status !== 'assigned') return errorResponse('CI is not in assigned status', 400, 'INVALID_STATUS');
  await db.from('credit_investigations').update({ status: 'accepted', response_at: new Date().toISOString() }).eq('id', ci_id);
  await db.from('loans').update({ status: 'ci_assigned' }).eq('id', ci.loan_id);
  await db.from('rider_profiles').update({ is_available: false }).eq('id', user.id);
  await writeAuditLog({ performedBy: user.id, action: 'ci_accept', tableName: 'credit_investigations', recordId: ci_id, ipAddress: ip });
  if (ci.assigned_by) await sendPushNotification({ userId: ci.assigned_by, title: 'CI Accepted', body: 'The rider has accepted the credit investigation assignment.', type: 'ci_accepted', referenceId: ci_id });
  return jsonResponse({ message: 'CI assignment accepted' });
}

// ── [moved from functions/ci-decline/index.ts] ──────────────────────────
async function handleCiDecline(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.RIDER);
  if (roleCheck) return roleCheck;
  const { ci_id, decline_reason } = await req.json();
  if (!ci_id) return errorResponse('ci_id is required', 400, 'VALIDATION_ERROR');
  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
  const { data: ci } = await db.from('credit_investigations').select('id, status, assigned_by, loan_id, rider_id').eq('id', ci_id).eq('rider_id', user.id).single();
  if (!ci) return errorResponse('CI not found', 404, 'NOT_FOUND');
  if (ci.status !== 'assigned') return errorResponse('CI is not in assigned status', 400, 'INVALID_STATUS');
  await db.from('credit_investigations').update({ status: 'declined', response_at: new Date().toISOString(), notes: decline_reason ?? null }).eq('id', ci_id);
  await db.from('loans').update({ status: 'under_review' }).eq('id', ci.loan_id);
  await db.from('rider_profiles').update({ is_available: true }).eq('id', user.id);
  await writeAuditLog({ performedBy: user.id, action: 'ci_decline', tableName: 'credit_investigations', recordId: ci_id, ipAddress: ip });
  if (ci.assigned_by) await sendPushNotification({ userId: ci.assigned_by, title: 'CI Declined', body: 'The rider has declined the CI assignment. Please reassign.', type: 'ci_declined', referenceId: ci_id });
  return jsonResponse({ message: 'CI declined' });
}