// supabase/functions/users-create-employee/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validateEmail, sanitizeString } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';

const DEFAULT_PASSWORD = '12345678';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const {
      first_name, middle_name, last_name, suffix,
      gender, civil_status, dob, email, phone_number,
      department, position, hired_at,
    } = body;

    if (!first_name || !last_name || !email || !phone_number || !department || !position) {
      return errorResponse('Required fields missing', 400, 'VALIDATION_ERROR');
    }
    if (!validateEmail(sanitizeString(email))) {
      return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    const { data: roleRow } = await db.from('roles').select('id').eq('name', 'employee').single();
    if (!roleRow) return errorResponse('Employee role not found', 500, 'SERVER_ERROR');

    const { data: authUser, error: createErr } = await db.auth.admin.createUser({
      email: email.trim().toLowerCase(),
      password: DEFAULT_PASSWORD,
      email_confirm: true,
    });

    if (createErr || !authUser?.user) {
      if (createErr?.message?.includes('already')) {
        return errorResponse('Email already registered', 409, 'DUPLICATE');
      }
      return errorResponse('Failed to create auth user', 500, 'SERVER_ERROR');
    }

    const { data: user, error: userErr } = await db.from('users').insert({
      id: authUser.user.id,
      role_id: roleRow.id,
      email: email.trim().toLowerCase(),
      phone_number: sanitizeString(phone_number),
      first_name: sanitizeString(first_name),
      middle_name: middle_name ? sanitizeString(middle_name) : null,
      last_name: sanitizeString(last_name),
      suffix: suffix ? sanitizeString(suffix) : null,
      account_status: 'active',
      force_password_change: true,
      created_by: authResult.id,
    }).select().single();

    if (userErr || !user) {
      await db.auth.admin.deleteUser(authUser.user.id);
      return errorResponse('Failed to create user record', 500, 'SERVER_ERROR');
    }

    await db.from('employee_profiles').insert({
      id: user.id,
      department: sanitizeString(department),
      position: sanitizeString(position),
      hired_at: hired_at ?? new Date().toISOString().split('T')[0],
      gender: gender ? sanitizeString(gender) : null,
      civil_status: civil_status ? sanitizeString(civil_status) : null,
    });

    await db.from('password_history').insert({
      user_id: user.id,
      password_hash: DEFAULT_PASSWORD,
    });

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'user_created',
      tableName: 'users',
      recordId: user.id,
      newValues: { role: 'employee', email, department, position },
      ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
    });

    return jsonResponse({ user_id: user.id, message: 'Employee created successfully' }, 201);
  } catch (err) {
    console.error('users-create-employee error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});