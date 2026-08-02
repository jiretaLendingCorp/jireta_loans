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
    let query = db.from('users')
      .select(`id, first_name, middle_name, last_name, suffix, email, phone, gender, account_status, 
        created_at, last_login_at, roles(name), lender_profiles(kyc_status, is_blacklisted),
        rider_profiles(vehicle_type, plate_number, is_available)`, { count: 'exact' })
      .not('roles.name', 'is', null);

    if (role) {
      query = query.eq('roles.name', role);
    } else if (user.role === ROLES.EMPLOYEE) {
      query = query.in('roles.name', ['rider', 'lender']);
    }

    if (status) query = query.eq('account_status', status);
    if (search) query = query.or(`first_name.ilike.%${search}%,last_name.ilike.%${search}%,email.ilike.%${search}%,phone.ilike.%${search}%`);

    query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch users', 500, 'SERVER_ERROR');

    return jsonResponse({
      data: data ?? [],
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
