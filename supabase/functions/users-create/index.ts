// supabase/functions/users-create/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   users-create-employee →  ?fn=create-employee
//   users-create-rider    →  ?fn=create-rider
//   users-create-lender   →  ?fn=create-lender
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validateEmail, sanitizeString, validatePhone, normalizeVehicleType } from '../_shared/validators.ts';
import { hashPassword } from '../_shared/password_hash.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

// ── [moved from users-create-employee] ──────────────────────────────────────
const DEFAULT_PASSWORD = '12345678';

// ── [moved from users-create-rider] ─────────────────────────────────────────
// Renamed from `DEFAULT_PASSWORD` to avoid a collision with users-create-employee.
const riderDefaultPassword = '12345678';

// ── [moved from users-create-lender] ────────────────────────────────────────
// Renamed from `DEFAULT_PASSWORD` to avoid a collision with users-create-employee.
const lenderDefaultPassword = '12345678';

// ── [moved from users-create-rider] ─────────────────────────────────────────
function toE164(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.startsWith('63')) return `+${digits}`;
  if (digits.startsWith('0')) return `+63${digits.slice(1)}`;
  return `+63${digits}`;
}

// ── [moved from users-create-lender] ────────────────────────────────────────
// Renamed from `toE164` to avoid a collision with users-create-rider.
function lenderToE164(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.startsWith('63')) return `+${digits}`;
  if (digits.startsWith('0')) return `+63${digits.slice(1)}`;
  return `+63${digits}`;
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'create-employee';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'create-employee':
        // ── [moved from functions/users-create-employee/index.ts] ───────
        return await handleCreateEmployee(req);
      case 'create-rider':
        // ── [moved from functions/users-create-rider/index.ts] ──────────
        return await handleCreateRider(req);
      case 'create-lender':
        // ── [moved from functions/users-create-lender/index.ts] ─────────
        return await handleCreateLender(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('users-create error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/users-create-employee/index.ts] ───────────────────
async function handleCreateEmployee(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;

  const body = await req.json();
  const {
    first_name, middle_name, last_name, suffix,
    gender, civil_status, email, phone_number,
    position, hired_at,
  } = body;

  if (!first_name || !last_name || !email || !phone_number || !position) {
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
    app_metadata: { role: 'employee' },
  });

  if (createErr || !authUser?.user) {
    if (createErr?.message?.includes('already')) {
      return errorResponse('Email already registered', 409, 'DUPLICATE');
    }
    return errorResponse('Failed to create auth user', 500, 'SERVER_ERROR');
  }

  const { data: user, error: userErr } = await db.from('users').upsert({
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
  }, { onConflict: 'id' }).select().single();

  if (userErr || !user) {
    await db.auth.admin.deleteUser(authUser.user.id);
    return errorResponse('Failed to create user record', 500, 'SERVER_ERROR');
  }

  await db.from('employee_profiles').insert({
    id: user.id,
    position: sanitizeString(position),
    hired_at: hired_at ?? new Date().toISOString().split('T')[0],
    gender: gender ? sanitizeString(gender) : null,
    civil_status: civil_status ? sanitizeString(civil_status) : null,
  });

  await db.from('password_history').insert({
    user_id: user.id,
    password_hash: await hashPassword(user.id, DEFAULT_PASSWORD),
  });

  await writeAuditLog({
    performedBy: authResult.id,
    action: 'user_created',
    tableName: 'users',
    recordId: user.id,
    newValues: { role: 'employee', email, position },
    ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
  });

  return jsonResponse({ user_id: user.id, message: 'Employee created successfully' }, 201);
}

// ── [moved from functions/users-create-rider/index.ts] ──────────────────────
async function handleCreateRider(req: Request) {
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
  const canonicalVehicleType = normalizeVehicleType(vehicle_type);
  if (!canonicalVehicleType) {
    return errorResponse('Invalid vehicle type', 400, 'VALIDATION_ERROR');
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
    password: riderDefaultPassword,
    phone_confirm: true,
    app_metadata: { role: 'rider' },
  });
  if (authErr || !authUser.user) {
    console.error('[users-create] rider auth user creation failed:', authErr?.message);
    return errorResponse('Failed to create auth user', 500, 'SERVER_ERROR');
  }

  const { data: roleData } = await db.from('roles').select('id').eq('name', 'rider').single();
  if (!roleData) return errorResponse('Rider role not found', 500, 'SERVER_ERROR');

  const { data: newUser, error: userErr } = await db.from('users').upsert({
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
  }, { onConflict: 'id' }).select('id').single();

  if (userErr) {
    await db.auth.admin.deleteUser(authUser.user.id);
    return errorResponse('Failed to create user record', 500, 'SERVER_ERROR');
  }

  const { error: riderProfileErr } = await db.from('rider_profiles').insert({
    id: newUser.id,
    vehicle_type: canonicalVehicleType,
    plate_number: sanitizeString(plate_number).toUpperCase(),
    drivers_license_number: sanitizeString(drivers_license_number),
    drivers_license_expiry: drivers_license_expiry || null,
    vehicle_brand: vehicle_brand ? sanitizeString(vehicle_brand) : null,
    is_available: true,
  });
  if (riderProfileErr) {
    await db.auth.admin.deleteUser(authUser.user.id);
    await db.from('users').delete().eq('id', newUser.id);
    console.error('[users-create] rider profile insert failed:', riderProfileErr.message);
    return errorResponse('Failed to save rider profile', 500, 'SERVER_ERROR');
  }

  await db.from('password_history').insert({
    user_id: newUser.id,
    password_hash: await hashPassword(newUser.id, riderDefaultPassword),
  });

  await writeAuditLog({ performedBy: user.id, action: 'create_rider', tableName: 'users', recordId: newUser.id, newValues: { role: 'rider', first_name, last_name, phone_number: phone.trim() }, ipAddress: ip });
  await sendPushNotification({ userId: user.id, title: 'Rider Created', body: `Rider ${first_name} ${last_name} has been created.`, type: 'user_created' });

  return jsonResponse({ message: 'Rider created successfully', user_id: newUser.id }, 201);
}

// ── [moved from functions/users-create-lender/index.ts] ─────────────────────
async function handleCreateLender(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const body = await req.json();
  const { first_name, middle_name, last_name, suffix, phone, gender, civil_status,
    dob, employment_type, employer_name, monthly_income, source_of_funds } = body;

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
    phone: lenderToE164(phone.trim()),
    password: lenderDefaultPassword,
    phone_confirm: true,
    app_metadata: { role: 'lender' },
  });
  if (authErr || !authUser.user) {
    console.error('[users-create] lender auth user creation failed:', authErr?.message);
    return errorResponse('Failed to create auth user', 500, 'SERVER_ERROR');
  }

  const { data: roleData } = await db.from('roles').select('id').eq('name', 'lender').single();
  if (!roleData) return errorResponse('Lender role not found', 500, 'SERVER_ERROR');

  const { data: newUser, error: userErr } = await db.from('users').upsert({
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
  }, { onConflict: 'id' }).select('id').single();

  if (userErr) {
    await db.auth.admin.deleteUser(authUser.user.id);
    return errorResponse('Failed to create user record', 500, 'SERVER_ERROR');
  }

  const { error: lenderProfileErr } = await db.from('lender_profiles').insert({
    id: newUser.id,
    gender: gender ? sanitizeString(gender).toLowerCase() : null,
    civil_status: civil_status ? sanitizeString(civil_status).toLowerCase() : null,
    date_of_birth: dob ?? null,
    employment_type: employment_type ? sanitizeString(employment_type).toLowerCase() : null,
    employer_name: employer_name ? sanitizeString(employer_name) : null,
    monthly_income: monthly_income ? Number(monthly_income) : null,
    source_of_funds: source_of_funds ? sanitizeString(source_of_funds).toLowerCase() : null,
    account_upgrade_status: 'not_submitted',
  });

  if (lenderProfileErr) {
    console.error('[users-create] lender profile insert failed:', lenderProfileErr.message);
    await db.auth.admin.deleteUser(authUser.user.id);
    return errorResponse('Failed to create lender profile', 500, 'SERVER_ERROR');
  }

  await db.from('password_history').insert({
    user_id: newUser.id,
    password_hash: await hashPassword(newUser.id, lenderDefaultPassword),
  });

  await writeAuditLog({ performedBy: user.id, action: 'create_lender', tableName: 'users', recordId: newUser.id, newValues: { role: 'lender', first_name, last_name, phone_number: phone.trim() }, ipAddress: ip });

  return jsonResponse({ message: 'Lender created successfully', user_id: newUser.id }, 201);
}