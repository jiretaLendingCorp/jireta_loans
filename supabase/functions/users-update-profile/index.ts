
// supabase/functions/users-update-profile/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString, validatePhone } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';

// Normalize display values (e.g. "Self-Employed") to the lowercase/underscored
// form the lender_profiles CHECK constraints expect (e.g. "self_employed").
function normalizeEnum(value: string | undefined | null): string | null {
  if (!value) return null;
  return sanitizeString(value).trim().toLowerCase().replace(/\s+/g, '_');
}

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
    const allowed = ['first_name', 'middle_name', 'last_name', 'suffix', 'profile_photo_url'];
    for (const f of allowed) {
      if (body[f] !== undefined) updateFields[f] = sanitizeString(body[f]);
    }
    if (body.avatar_url !== undefined) updateFields.profile_photo_url = sanitizeString(body.avatar_url);

    if (body.phone && body.phone !== existing.phone_number) {
      if (!validatePhone(sanitizeString(body.phone))) return errorResponse('Invalid phone', 400, 'VALIDATION_ERROR');
      const { data: taken } = await db.from('users').select('id').eq('phone_number', body.phone.trim()).neq('id', targetId).maybeSingle();
      if (taken) return errorResponse('Phone already used', 400, 'DUPLICATE');
      updateFields.phone_number = body.phone.trim();
    }

    if (body.fcm_token !== undefined) updateFields.fcm_token = body.fcm_token;

    if (Object.keys(updateFields).length > 0) {
      await db.from('users').update(updateFields).eq('id', targetId);
    }

    // Rider profile — accept both the flat mobile payload and the nested form.
    if (body.rider_profile || body.plate_number || body.drivers_license_number || body.vehicle_type || body.vehicle_brand) {
      const rp = body.rider_profile ?? body;
      await db.from('rider_profiles').update({
        vehicle_type: rp.vehicle_type ? sanitizeString(rp.vehicle_type) : undefined,
        plate_number: rp.plate_number ? sanitizeString(rp.plate_number).toUpperCase() : undefined,
        vehicle_brand: rp.vehicle_brand ? sanitizeString(rp.vehicle_brand) : undefined,
        drivers_license_number: rp.drivers_license_number ? sanitizeString(rp.drivers_license_number) : undefined,
        drivers_license_expiry: rp.drivers_license_expiry ?? undefined,
      }).eq('id', targetId);
    }

    // Lender profile — accept both the flat mobile payload and the nested form.
    const lp = body.lender_profile ?? (body.gender || body.civil_status || body.dob ||
      body.date_of_birth || body.employment_type || body.employer_name ||
      body.monthly_income || body.gcash_number || body.source_of_funds ||
      body.street_address || body.barangay || body.city || body.province || body.zip_code
      ? body : null);

    if (lp) {
      const dob = lp.dob ?? lp.date_of_birth;
      await db.from('lender_profiles').update({
        gender: lp.gender !== undefined && lp.gender !== null && lp.gender !== ''
          ? (normalizeEnum(lp.gender) ?? undefined)
          : undefined,
        civil_status: lp.civil_status !== undefined && lp.civil_status !== null && lp.civil_status !== ''
          ? (normalizeEnum(lp.civil_status) ?? undefined)
          : undefined,
        date_of_birth: dob ? String(dob).substring(0, 10) : undefined,
        employment_type: lp.employment_type !== undefined && lp.employment_type !== null && lp.employment_type !== ''
          ? (normalizeEnum(lp.employment_type) ?? undefined)
          : undefined,
        employer_name: lp.employer_name ? sanitizeString(lp.employer_name) : undefined,
        monthly_income: lp.monthly_income !== undefined && lp.monthly_income !== null && lp.monthly_income !== ''
          ? Number(lp.monthly_income)
          : undefined,
        gcash_number: lp.gcash_number ? sanitizeString(lp.gcash_number) : undefined,
        source_of_funds: lp.source_of_funds ? normalizeEnum(lp.source_of_funds) : undefined,
        street_address: lp.street_address ? sanitizeString(lp.street_address) : undefined,
        barangay: lp.barangay ? sanitizeString(lp.barangay) : undefined,
        city: lp.city ? sanitizeString(lp.city) : undefined,
        province: lp.province ? sanitizeString(lp.province) : undefined,
        zip_code: lp.zip_code ? sanitizeString(lp.zip_code) : undefined,
      }).eq('id', targetId);
    }

    if (body.employee_profile && ['head_manager'].includes(user.role)) {
      const ep = body.employee_profile;
      await db.from('employee_profiles').update({
        department: ep.department ? sanitizeString(ep.department) : undefined,
        position: ep.position ? sanitizeString(ep.position) : undefined,
      }).eq('id', targetId);
    }

    await writeAuditLog({ performedBy: user.id, action: 'update_profile', tableName: 'users', recordId: targetId, oldValues: existing, ipAddress: ip });

    return jsonResponse({ message: 'Profile updated successfully' });
  } catch (err) {
    console.error('users-update-profile error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
