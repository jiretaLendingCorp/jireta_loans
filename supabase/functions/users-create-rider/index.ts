// supabase/functions/users-create-rider/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString, validatePhone } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

const DEFAULT_PASSWORD = '12345678';

function toE164(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.startsWith('63')) return `+${digits}`;
  if (digits.startsWith('0')) return `+63${digits.slice(1)}`;
  return `+63${digits}`;
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { first_name, middle_name, last_name, suffix, phone, vehicle_type, plate_number,
      drivers_license_number, drivers_license_expiry, vehicle_brand } = body;

    if (!first_name || !last_name || !phone || !vehicle_type || !plate_number || !drivers_license_number) {
      return errorResponse('Missing required fields', 400, 'VALIDATION_ERROR');
    }
    if (!validatePhone(sanitizeString(phone))) {
      return errorResponse('Invalid phone number format (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: existingPhone } = await db.from('users').select('id').eq('phone_number', phone.trim()).maybeSingle();
    if (existingPhone) return errorResponse('Phone number already registered', 400, 'DUPLICATE');

    const { data: authUser, error: authErr } = await db.auth.admin.createUser({
      phone: toE164(phone.trim()),
      password: DEFAULT_PASSWORD,
      phone_confirm: true,
    });
    if (authErr || !authUser.user) return errorResponse('Failed to create auth user: ' + authErr?.message, 500, 'SERVER_ERROR');

    const { data: roleData } = await db.from('roles').select('id').eq('name', 'rider').single();
    if (!roleData) return errorResponse('Rider role not found', 500, 'SERVER_ERROR');

    const { data: newUser, error: userErr } = await db.from('users').insert({
      id: authUser.user.id,
      first_name: sanitizeString(first_name),
      middle_name: middle_name ? sanitizeString(middle_name) : null,
      last_name: sanitizeString(last_name),
      suffix: suffix ? sanitizeString(suffix) : null,
      phone_number: phone.trim(),
      role_id: roleData.id,
      account_status: 'active',
      force_password_change: true,
      created_by: user.id,
    }).select('id').single();

    if (userErr) {
      await db.auth.admin.deleteUser(authUser.user.id);
      return errorResponse('Failed to create user record', 500, 'SERVER_ERROR');
    }

    await db.from('rider_profiles').insert({
      id: newUser.id,
      vehicle_type: sanitizeString(vehicle_type),
      plate_number: sanitizeString(plate_number).toUpperCase(),
      drivers_license_number: sanitizeString(drivers_license_number),
      drivers_license_expiry: drivers_license_expiry || null,
      vehicle_brand: vehicle_brand ? sanitizeString(vehicle_brand) : null,
      is_available: true,
    });

    await writeAuditLog({ performedBy: user.id, action: 'create_rider', tableName: 'users', recordId: newUser.id, ipAddress: ip });
    await sendPushNotification({ userId: user.id, title: 'Rider Created', body: `Rider ${first_name} ${last_name} has been created.`, type: 'user_created' });

    return jsonResponse({ message: 'Rider created successfully', user_id: newUser.id }, 201);
  } catch (err) {
    console.error('users-create-rider error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});