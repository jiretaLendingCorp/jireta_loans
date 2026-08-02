
// supabase/functions/users-update-profile/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString, validatePhone } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const body = await req.json();
    const targetId = body.user_id ?? user.id;

    if (targetId !== user.id && !['head_manager', 'employee'].includes(user.role)) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: existing } = await db.from('users').select('*').eq('id', targetId).single();
    if (!existing) return errorResponse('User not found', 404, 'NOT_FOUND');

    const updateFields: Record<string, unknown> = {};
    const allowed = ['first_name', 'middle_name', 'last_name', 'suffix', 'gender', 'civil_status', 'dob', 'avatar_url'];
    for (const f of allowed) {
      if (body[f] !== undefined) updateFields[f] = sanitizeString(body[f]);
    }

    if (body.phone && body.phone !== existing.phone) {
      if (!validatePhone(sanitizeString(body.phone))) return errorResponse('Invalid phone', 400, 'VALIDATION_ERROR');
      const { data: taken } = await db.from('users').select('id').eq('phone', body.phone.trim()).neq('id', targetId).maybeSingle();
      if (taken) return errorResponse('Phone already used', 400, 'DUPLICATE');
      updateFields.phone = body.phone.trim();
    }

    if (body.fcm_token !== undefined) updateFields.fcm_token = body.fcm_token;

    if (Object.keys(updateFields).length > 0) {
      await db.from('users').update(updateFields).eq('id', targetId);
    }

    if (body.rider_profile && user.role !== 'lender' && user.role !== 'employee') {
      const rp = body.rider_profile;
      await db.from('rider_profiles').update({
        vehicle_type: rp.vehicle_type ? sanitizeString(rp.vehicle_type) : undefined,
        plate_number: rp.plate_number ? sanitizeString(rp.plate_number).toUpperCase() : undefined,
        vehicle_brand: rp.vehicle_brand ? sanitizeString(rp.vehicle_brand) : undefined,
      }).eq('user_id', targetId);
    }

    if (body.lender_profile) {
      const lp = body.lender_profile;
      await db.from('lender_profiles').update({
        employment_type: lp.employment_type ? sanitizeString(lp.employment_type) : undefined,
        employer_name: lp.employer_name ? sanitizeString(lp.employer_name) : undefined,
        monthly_income: lp.monthly_income ? Number(lp.monthly_income) : undefined,
        gcash_number: lp.gcash_number ? sanitizeString(lp.gcash_number) : undefined,
      }).eq('user_id', targetId);
    }

    if (body.employee_profile && ['head_manager'].includes(user.role)) {
      const ep = body.employee_profile;
      await db.from('employee_profiles').update({
        department: ep.department ? sanitizeString(ep.department) : undefined,
        position: ep.position ? sanitizeString(ep.position) : undefined,
      }).eq('user_id', targetId);
    }

    await writeAuditLog({ performedBy: user.id, action: 'update_profile', tableName: 'users', recordId: targetId, oldValues: existing, ipAddress: ip });

    return jsonResponse({ message: 'Profile updated successfully' });
  } catch (err) {
    console.error('users-update-profile error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});