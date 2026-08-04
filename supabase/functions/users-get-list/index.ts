// supabase/functions/users-get-list/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
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
      .select(`id, first_name, middle_name, last_name, suffix, email, phone_number, account_status, 
        created_at, last_login_at, roles!users_role_id_fkey(name),
        lender_profiles!lender_profiles_id_fkey(kyc_status, is_blacklisted, gender),
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

    const mapped = (data ?? []).map((u: any) => ({
      ...u,
      phone: u.phone_number,
      gender: u.lender_profiles?.gender ?? u.employee_profiles?.gender ?? null,
      department: u.employee_profiles?.department ?? null,
      position: u.employee_profiles?.position ?? null,
    }));

    return jsonResponse({
      data: mapped,
      total: count ?? 0,
      page,
      limit,
      totalPages: Math.ceil((count ?? 0) / limit),
    });
  } catch (err) {
    console.error('users-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
