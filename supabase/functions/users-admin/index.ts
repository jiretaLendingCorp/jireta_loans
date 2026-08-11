// supabase/functions/users-admin/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   users-get-list        →  ?fn=get-list
//   users-suspend-activate →  ?fn=suspend-activate
//   users-archive          →  ?fn=archive
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';
import { getLenderBlacklistBatch } from '../_shared/loan_financials.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-list';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'get-list':
        // ── [moved from functions/users-get-list/index.ts] ──────────────
        return await handleGetList(req);
      case 'suspend-activate':
        // ── [moved from functions/users-suspend-activate/index.ts] ──────
        return await handleSuspendActivate(req);
      case 'archive':
        // ── [moved from functions/users-archive/index.ts] ───────────────
        return await handleArchive(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('users-admin error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/users-get-list/index.ts] ──────────────────────────
async function handleGetList(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const url = new URL(req.url);
  const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
  const role = url.searchParams.get('role');
  const status = url.searchParams.get('status');
  const search = url.searchParams.get('search');
  const offset = (page - 1) * limit;

  if (user.role === ROLES.EMPLOYEE) {
    if (role && !['rider', 'lender'].includes(role)) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }
  }

  const db = getAdminClient();

  // Resolve role name -> id ONCE so we can filter the parent `users` rows
  // directly by role_id. Filtering on the bare `roles(name)` embed does NOT
  // restrict the parent rows (too-many embed), which let every role list show
  // all users mixed together.
  let roleIds: string[] | null = null;
  if (role) {
    const { data: roleRows } = await db
      .from('roles')
      .select('id')
      .eq('name', role);
    roleIds = (roleRows ?? []).map((r: any) => r.id);
    if (roleIds.length === 0) {
      return errorResponse('Invalid role', 400, 'VALIDATION_ERROR');
    }
  }

  let query = db.from('users')
    .select(`id, first_name, middle_name, last_name, suffix, email, phone_number, account_status, profile_photo_url,
      created_at, last_login_at, roles!users_role_id_fkey(name),
      lender_profiles!lender_profiles_id_fkey(kyc_status, gender),
      rider_profiles(vehicle_type, plate_number, is_available),
      employee_profiles(department, position, gender, civil_status)`, { count: 'exact' });

  if (roleIds) {
    query = query.in('role_id', roleIds);
  } else if (user.role === ROLES.EMPLOYEE) {
    // Employees may only see rider + lender lists.
    const { data: memberRows } = await db
      .from('roles')
      .select('id')
      .in('name', ['rider', 'lender']);
    query = query.in('role_id', (memberRows ?? []).map((r: any) => r.id));
  }

  if (status) query = query.eq('account_status', status);
  if (search) query = query.or(`first_name.ilike.%${search}%,last_name.ilike.%${search}%,email.ilike.%${search}%,phone_number.ilike.%${search}%`);

  query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);

  const { data, error, count } = await query;
  if (error) return errorResponse('Failed to fetch users', 500, 'SERVER_ERROR');

  const blacklistMap = await getLenderBlacklistBatch(
    db,
    (data ?? []).filter((u: any) => u.lender_profiles).map((u: any) => u.id),
  );

  const mapped = (data ?? []).map((u: any) => {
    const isBlacklisted = u.lender_profiles ? Boolean(blacklistMap[u.id]) : null;
    return {
      ...u,
      lender_profiles: u.lender_profiles ? { ...u.lender_profiles, is_blacklisted: isBlacklisted } : u.lender_profiles,
      is_blacklisted: isBlacklisted,
      phone: u.phone_number,
      gender: u.lender_profiles?.gender ?? u.employee_profiles?.gender ?? null,
      department: u.employee_profiles?.department ?? null,
      position: u.employee_profiles?.position ?? null,
    };
  });

  return jsonResponse({
    data: mapped,
    total: count ?? 0,
    page,
    limit,
    totalPages: Math.ceil((count ?? 0) / limit),
  });
}

// ── [moved from functions/users-suspend-activate/index.ts] ──────────────────
async function handleSuspendActivate(req: Request) {
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
}

// ── [moved from functions/users-archive/index.ts] ───────────────────────────
async function handleArchive(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;

  const { user_id } = await req.json();
  if (!user_id) return errorResponse('user_id is required', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: target } = await db.from('users').select('id, account_status, roles(name)').eq('id', user_id).single();
  if (!target) return errorResponse('User not found', 404, 'NOT_FOUND');
  if ((target as any).roles?.name === 'head_manager') return errorResponse('Cannot archive a Head Manager', 400, 'FORBIDDEN');
  if (target.account_status === 'archived') return errorResponse('User already archived', 400, 'INVALID_STATUS');

  const { count: activeLoans } = await db.from('loans').select('*', { count: 'exact', head: true })
    .eq('lender_id', user_id).in('status', ['pending', 'under_review', 'ci_assigned', 'ci_completed', 'active', 'overdue']);
  if ((activeLoans ?? 0) > 0) return errorResponse('Cannot archive user with active loans', 400, 'ACTIVE_LOAN_EXISTS');

  await db.from('users').update({ account_status: 'archived' }).eq('id', user_id);
  await writeAuditLog({ performedBy: user.id, action: 'archive_user', tableName: 'users', recordId: user_id, ipAddress: ip });

  return jsonResponse({ message: 'User archived successfully' });
}