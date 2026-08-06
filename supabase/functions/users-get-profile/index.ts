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
      .select(`id, first_name, middle_name, last_name, suffix, email, phone_number, account_status,
        force_password_change, last_login_at, created_at, profile_photo_url,
        roles(id, name),
        employee_profiles(department, position, hired_at, gender, civil_status),
        rider_profiles(vehicle_type, plate_number, drivers_license_number, drivers_license_expiry, vehicle_brand, is_available),
        lender_profiles!lender_profiles_id_fkey(employment_type, employer_name, monthly_income, gcash_number, kyc_status, is_blacklisted, gender, civil_status, date_of_birth, source_of_funds, street_address, barangay, city, province, zip_code)`)
      .eq('id', targetId)
      .single();

    if (error || !data) return errorResponse('User not found', 404, 'NOT_FOUND');

    const { data: emergencyContacts } = await db
      .from('emergency_contacts')
      .select('id, name, relationship, phone_number, address')
      .eq('lender_id', targetId);

    // Flatten nested profile rows onto the user so the mobile/web models can
    // read department, position, plate_number, etc. straight off the object.
    const emp = (data as any).employee_profiles ?? null;
    const rider = (data as any).rider_profiles ?? null;
    const lender = (data as any).lender_profiles ?? null;

    const flattened = {
      ...(data as any),
      department: emp?.department ?? null,
      position: emp?.position ?? null,
      hired_at: emp?.hired_at ?? null,
      gender: lender?.gender ?? emp?.gender ?? null,
      civil_status: lender?.civil_status ?? emp?.civil_status ?? null,
      plate_number: rider?.plate_number ?? null,
      drivers_license_number: rider?.drivers_license_number ?? null,
      drivers_license_expiry: rider?.drivers_license_expiry ?? null,
      vehicle_brand: rider?.vehicle_brand ?? null,
      vehicle_type: rider?.vehicle_type ?? null,
      is_available: rider?.is_available ?? null,
      employment_type: lender?.employment_type ?? null,
      employer_name: lender?.employer_name ?? null,
      monthly_income: lender?.monthly_income ?? null,
      gcash_number: lender?.gcash_number ?? null,
      kyc_status: lender?.kyc_status ?? null,
      is_blacklisted: lender?.is_blacklisted ?? null,
      date_of_birth: lender?.date_of_birth ?? null,
      source_of_funds: lender?.source_of_funds ?? null,
      street_address: lender?.street_address ?? null,
      barangay: lender?.barangay ?? null,
      city: lender?.city ?? null,
      province: lender?.province ?? null,
      zip_code: lender?.zip_code ?? null,
      emergency_contacts: emergencyContacts ?? [],
    };

    return jsonResponse({ user: flattened });
  } catch (err) {
    console.error('users-get-profile error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
