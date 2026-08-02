// supabase/functions/users-get-profile/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const url = new URL(req.url);
    const targetId = url.searchParams.get('user_id') ?? user.id;

    if (targetId !== user.id) {
      if (user.role === ROLES.RIDER || user.role === ROLES.LENDER) {
        return errorResponse('Access denied', 403, 'FORBIDDEN');
      }
      if (user.role === ROLES.EMPLOYEE) {
        const db = getAdminClient();
        const { data: targetUser } = await db.from('users').select('roles(name)').eq('id', targetId).single();
        const targetRole = (targetUser as any)?.roles?.name;
        if (!['rider', 'lender'].includes(targetRole)) {
          return errorResponse('Access denied', 403, 'FORBIDDEN');
        }
      }
    }

    const db = getAdminClient();
    const { data, error } = await db
      .from('users')
      .select(`id, first_name, middle_name, last_name, suffix, email, phone, gender, civil_status, dob,
        avatar_url, account_status, force_password_change, last_login_at, created_at,
        roles(id, name),
        employee_profiles(department, position, hired_at),
        rider_profiles(vehicle_type, plate_number, drivers_license_number, drivers_license_expiry, vehicle_brand, is_available),
        lender_profiles(employment_type, employer_name, monthly_income, gcash_number, kyc_status, is_blacklisted)`)
      .eq('id', targetId)
      .single();

    if (error || !data) return errorResponse('User not found', 404, 'NOT_FOUND');

    return jsonResponse({ user: data });
  } catch (err) {
    console.error('users-get-profile error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
