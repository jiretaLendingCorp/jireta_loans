// supabase/functions/blacklist-manage/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   blacklist-add     →  ?fn=add
//   blacklist-remove  →  ?fn=remove
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
const DEFAULT_ACTION = 'add';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'add':
        // ── [moved from functions/blacklist-add/index.ts] ───────────────
        return await handleBlacklistAdd(req);
      case 'remove':
        // ── [moved from functions/blacklist-remove/index.ts] ────────────
        return await handleBlacklistRemove(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('blacklist-manage error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/blacklist-add/index.ts] ───────────────────────────
async function handleBlacklistAdd(req: Request) {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const body = await req.json().catch(() => ({}));
    const { lender_id, reason } = body;

    if (!lender_id || !validateUUID(lender_id)) {
      return errorResponse('Valid lender_id is required', 400, 'VALIDATION_ERROR');
    }
    if (!reason || reason.trim().length < 5) {
      return errorResponse('A reason of at least 5 characters is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    const { data: lender } = await db
      .from('users')
      .select('id, first_name, last_name, roles(name)')
      .eq('id', lender_id)
      .single();

    if (!lender || (lender as any).roles?.name !== 'lender') {
      return errorResponse('Lender not found', 404, 'NOT_FOUND');
    }

    const { data: existing } = await db
      .from('blacklist')
      .select('id, is_active')
      .eq('lender_id', lender_id)
      .eq('is_active', true)
      .single();

    if (existing) {
      return errorResponse('Lender is already blacklisted', 400, 'DUPLICATE');
    }

    const { data: blacklistEntry, error: blErr } = await db
      .from('blacklist')
      .insert({
        lender_id,
        reason: sanitizeString(reason),
        added_by: authResult.id,
        is_active: true,
      })
      .select()
      .single();

    if (blErr) throw blErr;

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'blacklist_add',
      tableName: 'blacklist',
      recordId: blacklistEntry.id,
      newValues: { lender_id, reason },
    });

    await sendPushNotification({
      userId: lender_id,
      title: 'Account Blacklisted',
      body: 'Your account has been blacklisted. Please contact Jireta Loans for more information.',
      type: 'system',
      referenceId: blacklistEntry.id,
      sentBy: authResult.id,
    });

    return jsonResponse({ success: true, blacklist: blacklistEntry });
  } catch (err) {
    console.error('blacklist-add error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
}

// ── [moved from functions/blacklist-remove/index.ts] ────────────────────────
async function handleBlacklistRemove(req: Request) {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const body = await req.json().catch(() => ({}));
    const { lender_id } = body;

    if (!lender_id || !validateUUID(lender_id)) {
      return errorResponse('Valid lender_id is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    const { data: active } = await db
      .from('blacklist')
      .select('id')
      .eq('lender_id', lender_id)
      .eq('is_active', true)
      .single();

    if (!active) {
      return errorResponse('No active blacklist entry found for this lender', 404, 'NOT_FOUND');
    }

    await db
      .from('blacklist')
      .update({ is_active: false, removed_by: authResult.id, removed_at: new Date().toISOString() })
      .eq('id', active.id);

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'blacklist_remove',
      tableName: 'blacklist',
      recordId: active.id,
      newValues: { lender_id, is_active: false },
    });

    await sendPushNotification({
      userId: lender_id,
      title: 'Account Reinstated',
      body: 'Your account blacklist has been removed. You may now apply for loans.',
      type: 'system',
      referenceId: active.id,
      sentBy: authResult.id,
    });

    return jsonResponse({ success: true });
  } catch (err) {
    console.error('blacklist-remove error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
}