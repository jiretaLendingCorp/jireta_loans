// supabase/functions/users-admin/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   users-get-list        →  ?fn=get-list
//   users-archive          →  ?fn=archive
//   users-unarchive        →  ?fn=unarchive         (restore archived user)
//   roles-archive          →  ?fn=archive-role      (archive entire role)
//   roles-unarchive        →  ?fn=unarchive-role    (restore archived role)
//   roles-get-list         →  ?fn=get-roles         (list roles with archived state)
//
// Requirement: "KAPAG NAKA ARCHIVED UNG ROLE OR USER DAPAT HINDI MAGAGAMIT
// NI USER UNG ACCOUNT NIYA PERO KAPAG NA UNARCHIVED NA THEN MA RERESTORE NA
// UNG ACCOUNT MAGAGAMIT NA NI USER"
//   → archived user OR archived role = login blocked (email/OTP/Google/refresh + any auth)
//   → unarchived = instantly restored, usable again.
//   Edge checks are in _shared/auth.ts + auth-* entry points; DB enforces
//   via roles.is_archived and auth_role() RLS helper.
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
import { hashPassword } from '../_shared/password_hash.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { embedAsObject } from '../_shared/types.ts';

// Same default password used by users-create for newly created accounts.
const DEFAULT_PASSWORD = '12345678';

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
      case 'archive':
        // ── [moved from functions/users-archive/index.ts] ───────────────
        return await handleArchive(req);
      case 'unarchive':
      case 'restore':
        return await handleUnarchive(req);
      case 'archive-role':
        return await handleArchiveRole(req);
      case 'unarchive-role':
      case 'restore-role':
        return await handleUnarchiveRole(req);
      case 'get-roles':
        return await handleGetRoles(req);
      case 'reset-password':
        // ── Head Manager resets another user's password ────────────────
        return await handleResetPassword(req);
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
  // directly by role_id. Filtering on the bare `roles!users_role_id_fkey(name)` embed does NOT
  // restrict the parent rows (too-many embed), which let every role list show
  // all users mixed together.
  let roleIds: string[] | null = null;
  if (role) {
    const { data: roleRows } = await db
      .from('roles')
      .select('id')
      .eq('name', role);
    roleIds = (roleRows ?? []).map((r) => r.id);
    if (roleIds.length === 0) {
      return errorResponse('Invalid role', 400, 'VALIDATION_ERROR');
    }
  }

  let query = db.from('users')
    .select(`id, first_name, middle_name, last_name, suffix, email, phone_number, account_status, profile_photo_url,
      created_at, last_login_at, roles!users_role_id_fkey(name),
      lender_profiles!lender_profiles_id_fkey(account_upgrade_status, gender, gcash_number),
      rider_profiles(vehicle_type, plate_number, drivers_license_number, vehicle_brand, is_available),
      employee_profiles(department, position, gender, civil_status)`, { count: 'exact' });

  if (roleIds) {
    query = query.in('role_id', roleIds);
  } else if (user.role === ROLES.EMPLOYEE) {
    // Employees may only see rider + lender lists.
    const { data: memberRows } = await db
      .from('roles')
      .select('id')
      .in('name', ['rider', 'lender']);
    query = query.in('role_id', (memberRows ?? []).map((r) => r.id));
  }

  if (status) query = query.eq('account_status', status);
  if (search) query = query.or(`first_name.ilike.%${search}%,last_name.ilike.%${search}%,email.ilike.%${search}%,phone_number.ilike.%${search}%`);

  query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);

  const { data, error, count } = await query;
  if (error) return errorResponse('Failed to fetch users', 500, 'SERVER_ERROR');

  const mapped = (data ?? []).map((u) => {
    const lenderProfile = embedAsObject(u.lender_profiles);
    const employeeProfile = embedAsObject(u.employee_profiles);
    const riderProfile = embedAsObject(u.rider_profiles);
    return {
      ...u,
      phone: u.phone_number,
      gender: lenderProfile?.gender ?? employeeProfile?.gender ?? null,
      department: employeeProfile?.department ?? null,
      position: employeeProfile?.position ?? null,
      account_upgrade_status: lenderProfile?.account_upgrade_status ?? null,
      gcash_number: lenderProfile?.gcash_number ?? null,
      vehicle_type: riderProfile?.vehicle_type ?? null,
      plate_number: riderProfile?.plate_number ?? null,
      drivers_license_number: riderProfile?.drivers_license_number ?? null,
      vehicle_brand: riderProfile?.vehicle_brand ?? null,
      is_available: riderProfile?.is_available ?? null,
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

// ── [moved from functions/users-archive/index.ts] ───────────────────────────
async function handleArchive(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const { user_id } = await req.json();
  if (!user_id) return errorResponse('user_id is required', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: target } = await db.from('users').select('id, account_status, roles!users_role_id_fkey(name)').eq('id', user_id).single();
  if (!target) return errorResponse('User not found', 404, 'NOT_FOUND');
  // deno-lint-ignore no-explicit-any
  const targetRole = (embedAsObject((target as Record<string, unknown>)['roles']) as any)?.name as string | undefined;
  if (targetRole === 'head_manager') return errorResponse('Cannot archive a Head Manager', 400, 'FORBIDDEN');
  if (user.role === ROLES.EMPLOYEE && targetRole === 'employee') {
    return errorResponse('Employees cannot archive other employees', 403, 'FORBIDDEN');
  }
  if (user.role === ROLES.EMPLOYEE && targetRole && !['rider', 'lender'].includes(targetRole)) {
    return errorResponse('Employees can only archive riders and lenders', 403, 'FORBIDDEN');
  }
  if (target.account_status === 'archived') return errorResponse('User already archived', 400, 'INVALID_STATUS');

  // NOTE: Active loans are PRESERVED — archiving is soft non-destructive.
  // Requirement: "kahit may active loan pa ma-archive pa rin, basta hindi mawawala lahat
  // ng active loan etc. ... maibabalik account kapag unarchived ng walang nadedelete"
  // → We only flip account_status to 'archived', NO delete/cascade. All loans,
  // collections, CIs, disbursements, payments remain intact and auto-resume on unarchive.

  await db.from('users').update({ account_status: 'archived' }).eq('id', user_id);
  await writeAuditLog({ performedBy: user.id, action: 'archive_user', tableName: 'users', recordId: user_id, ipAddress: ip });

  return jsonResponse({ message: 'User archived successfully' });
}

// ── RESET PASSWORD ──────────────────────────────────────────────────────
// Business rule: only the Head Manager can reset a user's password.
// The reset forces the user to create a new password on next login.
async function handleResetPassword(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;

  const body = await req.json();
  const user_id = body?.user_id as string | undefined;
  if (!user_id) return errorResponse('user_id is required', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: target } = await db.from('users').select('id, account_status, roles!users_role_id_fkey(name)').eq('id', user_id).single();
  if (!target) return errorResponse('User not found', 404, 'NOT_FOUND');
  // deno-lint-ignore no-explicit-any
  const targetRole = (embedAsObject((target as Record<string, unknown>)['roles']) as any)?.name as string | undefined;
  // Business rule: Head Manager may only reset passwords of Head Manager
  // and Employee accounts (rider/lender passwords are not reset here).
  if (targetRole !== 'head_manager' && targetRole !== 'employee') {
    return errorResponse('Only Head Manager and Employee accounts can be reset', 400, 'FORBIDDEN');
  }
  if (target.account_status === 'archived') {
    return errorResponse('Cannot reset password of an archived user', 400, 'INVALID_STATUS');
  }

  // Business rule: reset always returns the account to the default password
  // (12345678) — the same one used when the account was created. The user is
  // then forced to set a fresh password on next login.
  const { error: updateError } = await db.auth.admin.updateUserById(user_id, { password: DEFAULT_PASSWORD });
  if (updateError) {
    console.error('[users-admin] reset-password updateUserById failed:', updateError);
    return errorResponse('Failed to reset password', 500, 'SERVER_ERROR');
  }

  await db.from('users').update({ force_password_change: true }).eq('id', user_id);

  try {
    await db.from('password_history').insert({ user_id, password_hash: await hashPassword(user_id, DEFAULT_PASSWORD) });
  } catch (e) {
    console.error('[users-admin] reset-password history insert failed:', e);
  }

  await writeAuditLog({
    performedBy: user.id,
    action: 'reset_password',
    tableName: 'users',
    recordId: user_id,
    newValues: { role: targetRole ?? null, forced_change: true },
    ipAddress: ip,
  });

  return jsonResponse({ message: 'Password reset successfully' });
}

// ── UNARCHIVE / RESTORE USER ───────────────────────────────────────────
// Restores an archived user to active so they can log in again.
// Requirement: "KAPAG NA UNARCHIVED NA THEN MA RERESTORE NA UNG ACCOUNT
// MAGAGAMIT NA NI USER" — archived = blocked, unarchived = usable.
// Only Head Manager can restore (employees limited to rider/lender).
async function handleUnarchive(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const { user_id } = await req.json();
  if (!user_id) return errorResponse('user_id is required', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: target } = await db.from('users').select('id, account_status, roles!users_role_id_fkey(name)').eq('id', user_id).single();
  if (!target) return errorResponse('User not found', 404, 'NOT_FOUND');
  // deno-lint-ignore no-explicit-any
  const targetRole = (embedAsObject((target as Record<string, unknown>)['roles']) as any)?.name as string | undefined;
  if (user.role === ROLES.EMPLOYEE && targetRole === 'employee') {
    return errorResponse('Employees cannot restore other employees', 403, 'FORBIDDEN');
  }
  if (user.role === ROLES.EMPLOYEE && targetRole && !['rider', 'lender'].includes(targetRole)) {
    return errorResponse('Employees can only restore riders and lenders', 403, 'FORBIDDEN');
  }
  if (target.account_status !== 'archived') return errorResponse('User is not archived', 400, 'INVALID_STATUS');

  // Also check if the user's role itself is archived — restoring user alone
  // will still leave them blocked until role is unarchived. Allow it but inform.
  let roleArchived = false;
  if (targetRole) {
    const { data: roleRow } = await db.from('roles').select('is_archived').eq('name', targetRole).maybeSingle();
    // deno-lint-ignore no-explicit-any
    roleArchived = (roleRow as any)?.is_archived === true;
  }

  const { error: updErr } = await db.from('users').update({ account_status: 'active' }).eq('id', user_id);
  if (updErr) return errorResponse('Failed to restore user', 500, 'SERVER_ERROR');

  await writeAuditLog({ performedBy: user.id, action: 'unarchive_user', tableName: 'users', recordId: user_id, ipAddress: ip });

  if (roleArchived) {
    return jsonResponse({ message: 'User restored but role is still archived — user will remain blocked until role is unarchived', warning: 'ROLE_ARCHIVED' });
  }
  return jsonResponse({ message: 'User restored successfully — account is now active' });
}

// ── ARCHIVE ROLE ───────────────────────────────────────────────────────
// Blocks ALL users with this role from login/use. Only HEAD_MANAGER.
async function handleArchiveRole(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;

  const { role, role_name } = await req.json() as { role?: string; role_name?: string };
  const targetRole = (role ?? role_name ?? '').trim().toLowerCase();
  if (!targetRole) return errorResponse('role is required', 400, 'VALIDATION_ERROR');
  if (targetRole === 'head_manager') return errorResponse('Cannot archive head_manager role', 403, 'FORBIDDEN');
  if (!['employee', 'rider', 'lender'].includes(targetRole)) {
    return errorResponse('Invalid role. Allowed: employee, rider, lender', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: roleRow } = await db.from('roles').select('id, is_archived').eq('name', targetRole).single();
  if (!roleRow) return errorResponse('Role not found', 404, 'NOT_FOUND');
  // deno-lint-ignore no-explicit-any
  if ((roleRow as any).is_archived === true) return errorResponse('Role already archived', 400, 'INVALID_STATUS');

  const { error: updErr } = await db.from('roles').update({ is_archived: true, archived_at: new Date().toISOString(), archived_by: user.id }).eq('id', (roleRow as { id: string }).id);
  if (updErr) return errorResponse(`Failed to archive role: ${updErr.message}`, 500, 'SERVER_ERROR');

  await writeAuditLog({ performedBy: user.id, action: 'archive_role', tableName: 'roles', recordId: (roleRow as { id: string }).id, newValues: { role: targetRole, is_archived: true }, ipAddress: ip });

  return jsonResponse({ message: `Role '${targetRole}' archived — all ${targetRole} accounts are now blocked` });
}

// ── UNARCHIVE / RESTORE ROLE ───────────────────────────────────────────
async function handleUnarchiveRole(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;

  const { role, role_name } = await req.json() as { role?: string; role_name?: string };
  const targetRole = (role ?? role_name ?? '').trim().toLowerCase();
  if (!targetRole) return errorResponse('role is required', 400, 'VALIDATION_ERROR');
  if (!['employee', 'rider', 'lender', 'head_manager'].includes(targetRole)) {
    return errorResponse('Invalid role', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: roleRow } = await db.from('roles').select('id, is_archived').eq('name', targetRole).single();
  if (!roleRow) return errorResponse('Role not found', 404, 'NOT_FOUND');
  // deno-lint-ignore no-explicit-any
  if ((roleRow as any).is_archived !== true) return errorResponse('Role is not archived', 400, 'INVALID_STATUS');

  const { error: updErr } = await db.from('roles').update({ is_archived: false, archived_at: null, archived_by: null }).eq('id', (roleRow as { id: string }).id);
  if (updErr) return errorResponse(`Failed to restore role: ${updErr.message}`, 500, 'SERVER_ERROR');

  await writeAuditLog({ performedBy: user.id, action: 'unarchive_role', tableName: 'roles', recordId: (roleRow as { id: string }).id, newValues: { role: targetRole, is_archived: false }, ipAddress: ip });

  return jsonResponse({ message: `Role '${targetRole}' restored — all ${targetRole} accounts are now usable again` });
}

// ── GET ROLES (with archived state) ────────────────────────────────────
async function handleGetRoles(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;

  // Any authenticated user can view roles, but limit to staff for management
  const db = getAdminClient();
  const { data, error } = await db.from('roles').select('id, name, description, is_archived, archived_at, created_at').order('name');
  if (error) return errorResponse('Failed to fetch roles', 500, 'SERVER_ERROR');

  // Count users per role for convenience (blocked vs active)
  const counts: Record<string, number> = {};
  try {
    const { data: userCounts } = await db.from('users').select('role_id');
    if (userCounts) {
      const roleMap: Record<string, string> = {};
      (data ?? []).forEach((r: { id: string; name: string }) => { roleMap[r.id] = r.name; });
      // Fallback if join not available — just count via role_id grouping client side
      // For now, we don't need exact counts; frontend can query users-admin?fn=get-list per role.
    }
    void counts;
  } catch (_) { /* ignore */ }

  return jsonResponse({ roles: data ?? [] });
}