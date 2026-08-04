// supabase/functions/users-create-lender/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString, validatePhone } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';

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
    const { first_name, middle_name, last_name, suffix, phone, gender, civil_status,
      dob, employment_type, employer_name, monthly_income, gcash_number } = body;

    if (!first_name || !last_name || !phone || !gender || !civil_status || !dob) {
      return errorResponse('Missing required fields', 400, 'VALIDATION_ERROR');
    }
    if (!validatePhone(sanitizeString(phone))) {
      return errorResponse('Invalid phone number (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');
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

    const { data: roleData } = await db.from('roles').select('id').eq('name', 'lender').single();
    if (!roleData) return errorResponse('Lender role not found', 500, 'SERVER_ERROR');

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

    const { error: lenderProfileErr } = await db.from('lender_profiles').insert({
      id: newUser.id,
      gender: gender ? sanitizeString(gender) : null,
      civil_status: civil_status ? sanitizeString(civil_status) : null,
      date_of_birth: dob ?? null,
      employment_type: employment_type ? sanitizeString(employment_type) : null,
      employer_name: employer_name ? sanitizeString(employer_name) : null,
      monthly_income: monthly_income ? Number(monthly_income) : null,
      gcash_number: gcash_number ? sanitizeString(gcash_number) : null,
      kyc_status: 'pending',
      is_blacklisted: false,
    });

    if (lenderProfileErr) {
      await db.auth.admin.deleteUser(authUser.user.id);
      return errorResponse('Failed to create lender profile: ' + lenderProfileErr.message, 500, 'SERVER_ERROR');
    }

    await writeAuditLog({ performedBy: user.id, action: 'create_lender', tableName: 'users', recordId: newUser.id, ipAddress: ip });

    return jsonResponse({ message: 'Lender created successfully', user_id: newUser.id }, 201);
  } catch (err) {
    console.error('users-create-lender error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});